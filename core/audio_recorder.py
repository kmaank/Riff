import numpy as np
from scipy.io import wavfile
import threading
import queue
import time
import os
import logging
from collections import deque

class AudioRecorderError(Exception):
    """Raised when recording fails."""
    pass


class AudioRecorder:
    def __init__(self, sample_rate=16000, channels=1, silence_threshold_ms=600, energy_threshold=0.01):
        self.sample_rate = sample_rate
        self.channels = channels
        self.recording = False
        self.audio_queue = queue.Queue()
        self.frames = []
        self.stream = None
        self._lock = threading.RLock()  # Re-entrant: stop_recording may call cleanup
        
        # VAD Settings
        self.silence_threshold_ms = silence_threshold_ms
        self.energy_threshold = energy_threshold
        self.silence_start_time = None
        self.on_auto_stop = None
        self._levels_lock = threading.Lock()
        self._recent_levels = deque([0.0] * 22, maxlen=22)
        self._latest_rms = 0.0
        self.peak_rms = 0.0
        self._level_peak = 0.0
        self._level_last_emit = 0.0
        logging.info(f"[AudioRecorder] Init: {sample_rate}Hz, {channels}ch, VAD Thresh={energy_threshold}")

    def _sounddevice(self):
        """Import PortAudio only when recording so launch does not prompt for the mic."""
        import sounddevice as sd
        return sd

    def calculate_energy(self, audio_chunk):
        """Calculate RMS energy of audio chunk."""
        if len(audio_chunk) == 0:
            return 0
        return np.sqrt(np.mean(audio_chunk ** 2))

    def callback(self, indata, frames, time_info, status):
        """Called for each audio block."""
        if status:
            logging.warning(f"[AudioRecorder] Stream status: {status}")
            
        # Only queue data if actually recording
        if not self.recording:
            return
            
        data = indata.copy()
        self.audio_queue.put(data)

        energy = self.calculate_energy(data)
        with self._levels_lock:
            self._latest_rms = float(energy)
            if energy > self.peak_rms:
                self.peak_rms = float(energy)
            self._level_peak = max(self._level_peak, float(energy))
            now = time.time()
            if now - self._level_last_emit >= 0.045:
                self._recent_levels.append(self._level_peak)
                self._level_peak = 0.0
                self._level_last_emit = now

        # VAD Check (only if callback provided)
        if self.on_auto_stop:
            if energy > self.energy_threshold:
                # Speech detected - reset silence timer
                self.silence_start_time = None
            else:
                # Silence
                if self.silence_start_time is None:
                    self.silence_start_time = time.time()
                else:
                    duration = (time.time() - self.silence_start_time) * 1000
                    if duration > self.silence_threshold_ms:
                        logging.info(f"[VAD] Silence detected ({duration:.0f}ms), auto-stopping...")
                        # Call auto-stop in a separate thread to avoid blocking callback
                        threading.Thread(target=self.on_auto_stop, daemon=True).start()
                        self.silence_start_time = None  # Reset to prevent multiple triggers

    def snapshot_levels(self):
        """Recent RMS values for the recording HUD. Returns (levels, latest)."""
        with self._levels_lock:
            return list(self._recent_levels), float(self._latest_rms)

    def start_recording(self, on_auto_stop=None):
        """Start audio recording. Returns True on success, raises AudioRecorderError on failure."""
        with self._lock:
            # Check if already recording
            if self.recording:
                if self.stream and self.stream.active:
                    logging.warning("[AudioRecorder] Already recording (stream active). Ignoring start request.")
                    return True  # Already recording, that's OK
                else:
                    # Stream died but flag is still set - force reset
                    logging.error("[AudioRecorder] CRITICAL: Recording flag set but stream dead/missing! Force resetting...")
                    logging.error(f"[AudioRecorder] State check: recording={self.recording}, stream={self.stream}, stream.active={self.stream.active if self.stream else 'N/A'}")
                    self._force_cleanup()
            
            try:
                logging.info("[AudioRecorder] Starting stream...")
                
                # Clear any stale data
                self.frames = []
                self.audio_queue = queue.Queue()
                self.silence_start_time = None
                self.on_auto_stop = on_auto_stop
                with self._levels_lock:
                    self._recent_levels = deque([0.0] * 22, maxlen=22)
                    self._latest_rms = 0.0
                    self.peak_rms = 0.0
                    self._level_peak = 0.0
                    self._level_last_emit = 0.0
                
                sd = self._sounddevice()
                sd.default.samplerate = self.sample_rate
                sd.default.channels = self.channels
                self.stream = sd.InputStream(
                    samplerate=self.sample_rate,
                    channels=self.channels,
                    callback=self.callback
                )
                self.stream.start()
                self.recording = True
                
                logging.info("[AudioRecorder] Stream started successfully.")
                return True
                
            except Exception as e:
                logging.critical(f"[AudioRecorder] Failed to start stream: {e}", exc_info=True)
                self._force_cleanup()
                raise AudioRecorderError(f"Could not start recording: {e}")

    def stop_recording(self, filename="temp_recording.wav", timeout=5.0):
        """
        Stop recording and save to file.
        
        Args:
            filename: Path to save WAV file
            timeout: Maximum seconds to wait for stream cleanup
            
        Returns:
            True if audio was saved successfully
            
        Raises:
            AudioRecorderError if recording wasn't active or save failed
        """
        with self._lock:
            if not self.recording:
                logging.warning("[AudioRecorder] stop_recording called but not recording!")
                raise AudioRecorderError("Not currently recording")

            logging.info("[AudioRecorder] Stopping recording...")
            self.recording = False
            stream_to_close = self.stream
            self.stream = None

            queued = self.audio_queue.qsize()
            logging.info("[AudioRecorder] Draining audio queue: approx %s blocks", queued)
            try:
                while not self.audio_queue.empty():
                    try:
                        self.frames.append(self.audio_queue.get_nowait())
                    except queue.Empty:
                        break

                if not self.frames:
                    logging.warning("[AudioRecorder] No audio captured.")
                    self._close_stream_object(stream_to_close, timeout)
                    raise AudioRecorderError("No audio data captured")

                audio_data = np.concatenate(self.frames, axis=0)

                min_samples = int(self.sample_rate * 0.3)
                if len(audio_data) < min_samples:
                    logging.warning(f"[AudioRecorder] Audio too short ({len(audio_data)} samples)")
                    self._close_stream_object(stream_to_close, timeout)
                    raise AudioRecorderError("Recording too short")

                audio_int16 = (audio_data * 32767).astype(np.int16)
                wavfile.write(filename, self.sample_rate, audio_int16)

                duration = len(audio_data) / self.sample_rate
                file_size = os.path.getsize(filename)
                rms = float(np.sqrt(np.mean(audio_data ** 2)))
                peak = float(np.max(np.abs(audio_data)))
                logging.info(
                    "[AudioRecorder] Recording saved: %.2fs, %s bytes, frames=%s, rms=%.5f, peak=%.5f, path=%s",
                    duration, file_size, len(self.frames), rms, peak, filename
                )
                if duration > 60:
                    logging.info(
                        "[AudioRecorder] LONG RECORDING: %.1f min — chunking/watchdog should extend",
                        duration / 60.0
                    )

            except AudioRecorderError:
                raise
            except Exception as e:
                logging.error(f"[AudioRecorder] Error saving file: {e}", exc_info=True)
                self._close_stream_object(stream_to_close, timeout)
                raise AudioRecorderError(f"Failed to save recording: {e}")

        # Close PortAudio after the WAV is on disk so a hung abort cannot delay paste.
        self._close_stream_object(stream_to_close, timeout)
        return True

    def _close_stream_object(self, stream, timeout):
        """Close a PortAudio stream without holding the recorder lock."""
        if not stream:
            return True

        def close_stream():
            try:
                stream.abort()
            except Exception as e:
                logging.warning(f"[AudioRecorder] Stream abort failed: {e}")
            try:
                stream.close()
            except Exception as e:
                logging.warning(f"[AudioRecorder] Stream close failed: {e}")

        close_thread = threading.Thread(target=close_stream, daemon=True)
        close_thread.start()
        close_thread.join(timeout=timeout)

        if close_thread.is_alive():
            logging.warning("[AudioRecorder] Stream close still running after %.1fs — continuing", timeout)
            return False

        logging.info("[AudioRecorder] Stream closed.")
        return True

    def _close_stream_with_timeout(self, timeout):
        """Close self.stream with timeout protection. Returns True if closed successfully."""
        stream = self.stream
        self.stream = None
        return self._close_stream_object(stream, timeout)

    def _force_cleanup(self):
        """Force cleanup of all state without waiting. Thread-safe."""
        logging.warning("[AudioRecorder] Force cleanup triggered")

        # CRITICAL FIX: Use lock to ensure state changes are visible across threads
        with self._lock:
            self.recording = False
            self.frames = []
            self.silence_start_time = None
            self.on_auto_stop = None

            # Try to close stream but don't wait
            if self.stream:
                try:
                    self.stream.abort()
                except:
                    pass
                try:
                    self.stream.close()
                except:
                    pass
                self.stream = None

        logging.info("[AudioRecorder] Force cleanup completed")

    def is_active(self):
        """Check if currently recording."""
        return self.recording and self.stream is not None and self.stream.active

    def health_check(self):
        """
        Check recorder health and detect inconsistent states.
        Returns: (is_healthy: bool, issues: list[str])
        """
        issues = []

        with self._lock:
            # Check for zombie states
            if self.recording and not self.stream:
                issues.append("Recording flag set but no stream exists")

            if self.recording and self.stream and not self.stream.active:
                issues.append("Recording flag set but stream is inactive")

            if not self.recording and self.stream and self.stream.active:
                issues.append("Stream active but recording flag not set")

            # Log health status
            if issues:
                logging.warning(f"[AudioRecorder] Health check FAILED: {', '.join(issues)}")
                return False, issues
            else:
                return True, []

    def auto_recover(self):
        """Attempt to automatically recover from inconsistent states."""
        is_healthy, issues = self.health_check()

        if not is_healthy:
            logging.warning(f"[AudioRecorder] Auto-recovery triggered. Issues: {issues}")
            self._force_cleanup()
            return True

        return False

    def cancel_recording(self):
        """Cancel recording without saving."""
        with self._lock:
            if self.recording:
                logging.info("[AudioRecorder] Cancelling recording")
                self.recording = False
                self._close_stream_with_timeout(2.0)
                self.frames = []


def main():
    """Interactive test of AudioRecorder."""
    from pynput import keyboard
    
    logging.basicConfig(level=logging.INFO)
    
    recorder = AudioRecorder()
    
    def on_stop():
        print("Auto-stop triggered!")
        try:
            recorder.stop_recording("test_recording.wav")
            print("Recording saved!")
        except AudioRecorderError as e:
            print(f"Recording failed: {e}")
    
    print("Press and hold F8 to record (VAD enabled)...")
    print("Press ESC to exit")

    def on_press(key):
        if key == keyboard.Key.f8:
            try:
                recorder.start_recording(on_stop)
                print("Recording started...")
            except AudioRecorderError as e:
                print(f"Failed to start: {e}")
        elif key == keyboard.Key.esc:
            return False

    def on_release(key):
        if key == keyboard.Key.f8:
            try:
                recorder.stop_recording("test_recording.wav")
                print("Recording saved to test_recording.wav")
            except AudioRecorderError as e:
                print(f"Recording failed: {e}")

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()

if __name__ == "__main__":
    main()