
import sounddevice as sd
import numpy as np
from scipy.io import wavfile
from pynput import keyboard
import threading
import queue
import time
import os

class AudioRecorder:
    def __init__(self, sample_rate=16000, channels=1, silence_threshold_ms=600, energy_threshold=0.01):
        self.sample_rate = sample_rate
        self.channels = channels
        self.recording = False
        self.audio_queue = queue.Queue()
        self.frames = []
        self.stream = None
        
        # VAD Settings
        self.silence_threshold_ms = silence_threshold_ms
        self.energy_threshold = energy_threshold
        self.silence_start_time = None
        self.on_auto_stop = None # Callback function
        
        # Audio device configuration
        sd.default.samplerate = self.sample_rate
        sd.default.channels = self.channels

    def calculate_energy(self, audio_chunk):
        """Calculate RMS energy of audio chunk."""
        if len(audio_chunk) == 0:
            return 0
        return np.sqrt(np.mean(audio_chunk ** 2))

    def callback(self, indata, frames, time_info, status):
        """Called for each audio block."""
        if status:
            print(f"Audio status: {status}")
            
        data = indata.copy()
        self.audio_queue.put(data)
        
        # VAD Check
        if self.recording and self.on_auto_stop:
            energy = self.calculate_energy(data)
            
            if energy > self.energy_threshold:
                # Speech detected
                self.silence_start_time = None
            else:
                # Silence
                if self.silence_start_time is None:
                    self.silence_start_time = time.time()
                else:
                    duration = (time.time() - self.silence_start_time) * 1000
                    if duration > self.silence_threshold_ms:
                         # Silence exceeded threshold -> Auto Stop
                         # We need to run this in a thread or separate call because
                         # we can't block the audio callback
                         print("[VAD] Silence detected, auto-stopping...")
                         self.on_auto_stop()

    def start_recording(self, on_auto_stop=None):
        if self.recording:
            return
            
        print("[Recording started]")
        self.recording = True
        self.frames = []
        self.audio_queue = queue.Queue()
        self.silence_start_time = None
        self.on_auto_stop = on_auto_stop
        
        self.stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            callback=self.callback
        )
        self.stream.start()
        
    def stop_recording(self, filename="temp_recording.wav"):
        if not self.recording:
            return

        self.recording = False
        
        # Stop stream
        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None
            
        # Collect data
        while not self.audio_queue.empty():
            self.frames.append(self.audio_queue.get())
            
        if not self.frames:
            print("No audio captured.")
            return

        # Save file
        audio_data = np.concatenate(self.frames, axis=0)
        audio_int16 = (audio_data * 32767).astype(np.int16)
        wavfile.write(filename, self.sample_rate, audio_int16)
        
        duration = len(audio_data) / self.sample_rate
        print(f"[Recording stopped: {duration:.2f} seconds]")

def main():
    def on_stop():
        print("Auto-stop triggered!")
        recorder.stop_recording()
        
    recorder = AudioRecorder()
    print("Press and hold F8 to record (VAD enabled)...")

    # Only minimal test here
    with keyboard.Listener(
        on_press=lambda k: recorder.start_recording(on_stop) if k == keyboard.Key.f8 else None,
        on_release=lambda k: recorder.stop_recording() if k == keyboard.Key.f8 else None
    ) as listener:
        listener.join()

if __name__ == "__main__":
    main()
