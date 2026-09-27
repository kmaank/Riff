
from groq import Groq
import os
import sys
import logging
import time
import re
import tempfile
import numpy as np
from scipy.io import wavfile
from utils.config_manager import GROQ_CHAT_MODEL

class TranscriptionError(Exception):
    pass

class Transcriber:
    # Script mode prompts for Whisper
    # Note: Constraining prompts prevent hallucinations. Be explicit about "exactly", "verbatim", "do not add".
    # CRITICAL: Tell Whisper to output NOTHING if there's no speech to prevent hallucinations.
    SCRIPT_MODE_PROMPTS = {
        "english_mixed": "Transcribe exactly what is spoken, word for word. Keep both English and non-English words as heard. Do not add explanations, context, or extra words. If there is no speech or only silence/noise, output nothing. Output only the verbatim speech.",
        "english_translated": "Transcribe the spoken audio exactly as heard, translating any non-English words to English. If there is no speech or only silence/noise, output nothing. Output only what was actually said, without additions or explanations.",
        "original_mixed": "Transcribe exactly what is spoken, word for word, in the original language and script. Do not add explanations or extra words. If there is no speech or only silence/noise, output nothing. Output only the verbatim speech."
    }

    def __init__(self, api_key: str, script_mode: str = "english_mixed"):
        if not api_key:
            raise TranscriptionError("API key is required.")
        try:
            self.client = Groq(api_key=api_key, timeout=300.0)
            self._api_key = api_key
            self.script_mode = script_mode
            self.max_file_size_mb = 25  # Groq limit
            self.chunk_duration_minutes = 10  # Safe chunk size (well under 13 min limit)
            logging.info(f"[Transcriber] Init: script_mode={script_mode}")
            self.last_meta = {"likely_noise": False, "discarded_text": "", "no_speech_prob": None}
        except Exception as e:
            raise TranscriptionError(f"Failed to initialize Groq client: {e}")

    def _is_silence(self, filepath: str, rms_threshold: float = 0.002) -> bool:
        """Skip Groq when the clip is effectively silence so paid keys are not billed."""
        try:
            _rate, data = wavfile.read(filepath)
            x = np.asarray(data, dtype=np.float32)
            if x.ndim > 1:
                x = x[:, 0]
            if x.size == 0:
                return True
            peak = float(np.max(np.abs(x)))
            if peak > 1.5:
                x = x / 32768.0
            rms = float(np.sqrt(np.mean(x ** 2)))
            logging.info(f"[Transcriber] Audio RMS={rms:.5f} threshold={rms_threshold}")
            return rms < rms_threshold
        except Exception as e:
            logging.warning(f"[Transcriber] Silence check failed, sending to Groq: {e}")
            return False

    def update_api_key(self, api_key: str):
        if not api_key or api_key == getattr(self, "_api_key", None):
            return
        self._api_key = api_key
        self.client = Groq(api_key=api_key, timeout=300.0)
        
    def _transcribe_chunked(self, filepath: str) -> str:
        """
        Transcribe large audio file by splitting into chunks.
        Returns concatenated transcription of all chunks.
        """
        chunk_files = []
        try:
            # Split audio into chunks
            chunk_files = self._split_audio_file(filepath)

            # Transcribe each chunk
            all_transcriptions = []
            for i, chunk_path in enumerate(chunk_files):
                chunk_started = time.time()
                try:
                    logging.info(f"[Transcriber] Transcribing chunk {i+1}/{len(chunk_files)}...")
                    print(f"[Transcribing chunk {i+1}/{len(chunk_files)}...]")
                    
                    # Transcribe chunk (this will call the single-file logic below)
                    chunk_text = self._transcribe_single_file(chunk_path)
                    elapsed = time.time() - chunk_started
                    
                    if chunk_text and chunk_text.strip():
                        all_transcriptions.append(chunk_text.strip())
                        logging.info(
                            "[Transcriber] Chunk %s/%s result: %s chars in %.1fs",
                            i + 1, len(chunk_files), len(chunk_text), elapsed
                        )
                    else:
                        logging.warning(
                            "[Transcriber] Chunk %s/%s empty after %.1fs",
                            i + 1, len(chunk_files), elapsed
                        )
                        
                except Exception as e:
                    logging.error(
                        "[Transcriber] Failed to transcribe chunk %s after %.1fs: %s",
                        i + 1, time.time() - chunk_started, e
                    )
                    # Continue with other chunks even if one fails
                    continue

            # Concatenate all transcriptions with space separator
            if not all_transcriptions:
                logging.warning("[Transcriber] No successful transcriptions from any chunk")
                return ""

            final_text = " ".join(all_transcriptions)
            logging.info(f"[Transcriber] Chunked transcription complete: {len(final_text)} total chars from {len(all_transcriptions)} chunks")
            print(f"[Chunked transcription complete: {len(all_transcriptions)} chunks processed]")

            return final_text

        finally:
            # Clean up temporary chunk files
            for chunk_path in chunk_files:
                try:
                    if os.path.exists(chunk_path):
                        os.remove(chunk_path)
                        logging.debug(f"[Transcriber] Deleted chunk: {chunk_path}")
                except Exception as e:
                    logging.warning(f"[Transcriber] Failed to delete chunk {chunk_path}: {e}")

    def _split_audio_file(self, filepath: str) -> list:
        """
        Split large audio file into chunks that fit within API limits.
        Returns list of temporary chunk file paths.
        """
        try:
            # Read WAV file
            sample_rate, audio_data = wavfile.read(filepath)

            # Calculate chunk size in samples
            chunk_duration_seconds = self.chunk_duration_minutes * 60
            chunk_size_samples = int(sample_rate * chunk_duration_seconds)

            # Split audio into chunks
            num_chunks = int(np.ceil(len(audio_data) / chunk_size_samples))
            logging.info(f"[Transcriber] Splitting {len(audio_data) / sample_rate / 60:.1f} min audio into {num_chunks} chunks of {self.chunk_duration_minutes} min each")

            chunk_files = []
            for i in range(num_chunks):
                start_idx = i * chunk_size_samples
                end_idx = min((i + 1) * chunk_size_samples, len(audio_data))
                chunk_data = audio_data[start_idx:end_idx]

                # Save chunk to temporary file
                chunk_file = tempfile.NamedTemporaryFile(suffix=f"_chunk_{i}.wav", delete=False)
                chunk_path = chunk_file.name
                chunk_file.close()

                wavfile.write(chunk_path, sample_rate, chunk_data)
                chunk_files.append(chunk_path)

                chunk_size_mb = os.path.getsize(chunk_path) / (1024 * 1024)
                logging.info(f"[Transcriber] Created chunk {i+1}/{num_chunks}: {chunk_size_mb:.2f} MB")

            return chunk_files

        except Exception as e:
            logging.error(f"[Transcriber] Failed to split audio file: {e}", exc_info=True)
            raise TranscriptionError(f"Failed to split audio file: {e}")

    def _transcribe_single_file(self, filepath: str) -> str:
        """
        Transcribe a single audio file (must be under size limit).
        Internal method used by both transcribe_file and _transcribe_chunked.
        """
        start_time = time.time()
        try:
            # Get prompt for script mode
            prompt = self.SCRIPT_MODE_PROMPTS.get(self.script_mode, self.SCRIPT_MODE_PROMPTS["english_mixed"])
            logging.info(f"[Transcriber] Using script_mode: {self.script_mode}")

            with open(filepath, "rb") as file:
                audio_bytes = file.read()
                api_params = {
                    "file": (filepath, audio_bytes),
                    "model": "whisper-large-v3",
                    "response_format": "verbose_json",
                    "prompt": prompt,
                    "temperature": 0.0,
                }

                # language="en" on transcriptions does NOT translate — it forces
                # English recognition and mangles Hindi/Hinglish. Use the
                # translations endpoint, then LLM post-process as backup.
                if self.script_mode == "english_translated":
                    try:
                        transcription = self.client.audio.translations.create(
                            file=api_params["file"],
                            model=api_params["model"],
                            prompt=prompt,
                            temperature=0.0,
                        )
                        logging.info("[Transcriber] english_translated: used translations API")
                    except Exception as e:
                        logging.warning(
                            "[Transcriber] translations API failed (%s); using transcriptions + LLM",
                            e,
                        )
                        transcription = self.client.audio.transcriptions.create(**api_params)
                else:
                    transcription = self.client.audio.transcriptions.create(**api_params)
            
            latency = (time.time() - start_time) * 1000
            logging.info(
                "[Transcriber] Success: %s chars in %.0fms (file=%s)",
                len(transcription.text), latency, os.path.basename(filepath)
            )
            print("[Transcription complete]")
            text = transcription.text.strip()
            logging.info(f"[Transcriber] Whisper Raw Output: {text}")

            # Check confidence scores to detect hallucinations (verbose_json provides these)
            if hasattr(transcription, 'segments') and transcription.segments:
                # Calculate average no_speech probability across segments
                total_no_speech_prob = 0
                segment_count = 0
                for segment in transcription.segments:
                    if hasattr(segment, 'no_speech_prob'):
                        total_no_speech_prob += segment.no_speech_prob
                        segment_count += 1

                if segment_count > 0:
                    avg_no_speech_prob = total_no_speech_prob / segment_count
                    logging.info(f"[Transcriber] Avg no_speech probability: {avg_no_speech_prob:.3f}")

                    # If average no_speech probability is very high, likely hallucination
                    if avg_no_speech_prob > 0.8:
                        logging.warning(f"[Transcriber] High no_speech probability ({avg_no_speech_prob:.3f}), likely hallucination")
                        self.last_meta = {
                            "likely_noise": True,
                            "discarded_text": text,
                            "no_speech_prob": avg_no_speech_prob,
                        }
                        return ""
                    self.last_meta["no_speech_prob"] = avg_no_speech_prob

            # Post-process based on script mode
            text = self._post_process_script_mode(text)

            # Filter Hallucinations (Aggressive)
            # 1. Exact Match List (Common Whisper glitches)
            HALLUCINATIONS_EXACT = [
                ".", "..", "...",
                "MBC News", "Amara.org",
                "Thank you for watching", "Thank you for watching.",
                "Thanks for watching", "Thanks for watching.",
                "No audio", "No audio.", "no audio", "no audio.",
                "Subtitles by", "Subtitle by", "aaa aaaa"
            ]

            if text in HALLUCINATIONS_EXACT or not text:
                logging.warning(f"[Transcriber] Filtered exact hallucination: '{text}'")
                print(f"[Filtered Hallucination (Exact): '{text}']")
                self.last_meta = {
                    "likely_noise": True,
                    "discarded_text": text,
                    "no_speech_prob": self.last_meta.get("no_speech_prob"),
                }
                return ""

            # 2. Regex Patterns (Subtitle credits, bracketed noise)
            # Note: Only filter patterns that are CLEARLY hallucinations, not legitimate content
            HALLUCINATION_PATTERNS = [
                 r"^\[.*\]$",          # Pure bracketed content: [Music], [Silence]
                 r"^\(.*\)$",          # Pure parenthetical: (Applause), (Music)
                 r"^Subtitle.*",       # Subtitle by...
                 r"^Translated by.*",  # Translated by...
                 r"^Thanks?(\s+you)?(\s+for\s+watching)?\.?$",  # Thank(s) (you) (for watching)
                 r"^Please subscribe",     # Common YouTube outro
                 r"^(No\s+)?audio(\s+(not\s+)?(detected|found|available))?\.?$",  # No audio (detected/found/available)
            ]

            for pattern in HALLUCINATION_PATTERNS:
                if re.search(pattern, text, re.IGNORECASE):
                     logging.warning(f"[Transcriber] Filtered regex hallucination: '{text}' (Pattern: {pattern})")
                     print(f"[Filtered Hallucination (Regex): '{text}']")
                     self.last_meta = {
                         "likely_noise": True,
                         "discarded_text": text,
                         "no_speech_prob": self.last_meta.get("no_speech_prob"),
                     }
                     return ""

            self.last_meta["likely_noise"] = False
            self.last_meta["discarded_text"] = ""
            return text

        except Exception as e:
            logging.error(f"[Transcriber] Failed: {e}", exc_info=True)
            raise TranscriptionError(f"Transcription failed: {e}")

    def transcribe_file(self, filepath: str) -> str:
        """
        Main transcription method. Automatically handles large files by chunking.
        Groq Whisper fails around ~13 minutes even when the WAV is under 25MB,
        so we split on duration as well as size.
        """
        if not os.path.exists(filepath):
            logging.error(f"[Transcriber] File not found: {filepath}")
            raise TranscriptionError(f"File not found: {filepath}")

        file_size_bytes = os.path.getsize(filepath)
        file_size_mb = file_size_bytes / (1024 * 1024)
        duration_sec = self._audio_duration_sec(filepath)
        logging.info(
            "[Transcriber] Request: %s (%.2f MB, %.1fs)",
            filepath, file_size_mb, duration_sec
        )

        self.last_meta = {"likely_noise": False, "discarded_text": "", "no_speech_prob": None}
        if self._is_silence(filepath):
            logging.info("[Transcriber] Audio is silence/noise — skipping Groq")
            self.last_meta = {"likely_noise": True, "discarded_text": "", "no_speech_prob": 1.0}
            return ""

        needs_chunk = (
            file_size_mb > self.max_file_size_mb
            or duration_sec > (self.chunk_duration_minutes * 60)
        )
        if needs_chunk:
            logging.warning(
                "[Transcriber] Splitting: size=%.2fMB (limit=%sMB) duration=%.1fs (chunk=%smin)",
                file_size_mb, self.max_file_size_mb, duration_sec, self.chunk_duration_minutes
            )
            print(f"[Large file detected: {file_size_mb:.1f}MB / {duration_sec/60:.1f} min. Splitting into chunks...]")
            return self._transcribe_chunked(filepath)

        print("[Transcribing...]")
        return self._transcribe_single_file(filepath)

    def _audio_duration_sec(self, filepath: str) -> float:
        try:
            sample_rate, audio_data = wavfile.read(filepath)
            if audio_data is None or len(audio_data) == 0:
                return 0.0
            return float(len(audio_data)) / float(sample_rate or 16000)
        except Exception as e:
            logging.warning("[Transcriber] Could not read duration from WAV: %s", e)
            size = max(0, os.path.getsize(filepath) - 44)
            return size / 32000.0

    def _post_process_script_mode(self, text: str) -> str:
        """
        Post-process transcription based on script mode.
        For english_mixed: Romanize non-English characters
        For english_translated: Ensure full translation to English
        For original_mixed: Keep as-is
        """
        if not text:
            return text

        if self.script_mode == "original_mixed":
            logging.info("[Transcriber] script_mode=original_mixed: keeping Whisper output as-is")
            return text

        elif self.script_mode == "english_mixed":
            return self._romanize_text(text)

        elif self.script_mode == "english_translated":
            return self._translate_to_english(text)

        return text

    def _romanize_text(self, text: str) -> str:
        """Romanize non-Latin characters for english_mixed mode."""
        # Check if text contains non-Latin characters (Devanagari, Arabic, etc.)
        has_non_latin = any(ord(char) > 127 and char not in '.,!?;:\'"()[]{}' for char in text)

        if not has_non_latin:
            logging.info("[Transcriber] script_mode=%s: text is Latin-only, skip romanize", self.script_mode)
            return text

        # Use LLM to romanize non-English text
        logging.info(f"[Transcriber] Romanizing text for english_mixed mode: {text[:50]}...")

        try:
            romanization_prompt = """You are a romanization expert. The user has dictated text that contains non-English words in their original script (e.g., Devanagari, Arabic).

Your task: Convert ONLY the non-English words to romanized Latin script. Keep English words unchanged.

CRITICAL RULES:
1. DO NOT translate - only romanize (convert script)
2. Keep code-switching natural
3. Preserve the meaning and pronunciation
4. Output ONLY the romanized text, nothing else

Examples:
- Input: "मुझे लगता है we should meet"
  Output: "Mujhe lagta hai we should meet"

- Input: "यह बहुत अच्छा है this is great"
  Output: "Yah bahut accha hai this is great"

Now romanize this text:"""

            response = self.client.chat.completions.create(
                model=GROQ_CHAT_MODEL,
                messages=[
                    {"role": "system", "content": romanization_prompt},
                    {"role": "user", "content": text}
                ],
                temperature=0.1,  # Low temperature for consistent romanization
                max_tokens=2048
            )

            romanized_text = self._chat_text(response)
            if not romanized_text:
                logging.warning("[Transcriber] Romanize returned empty; keeping original")
                return text
            logging.info(f"[Transcriber] Romanized: {romanized_text[:50]}...")

            return romanized_text

        except Exception as e:
            logging.error(f"[Transcriber] Romanization failed: {e}, returning original text")
            return text

    def _translate_to_english(self, text: str) -> str:
        """Translate text to English for english_translated mode."""
        # Check if text might contain non-English words
        # Simple heuristic: if already set language="en", Whisper should translate
        # But we double-check and translate any remaining non-English if needed

        # If text is very short or looks fully English, return as-is
        if len(text.split()) <= 2:
            logging.info("[Transcriber] script_mode=english_translated: short text, skip extra translate")
            return text

        # Check if there's likely non-English content
        # We'll use the LLM to ensure everything is in English
        logging.info(f"[Transcriber] Ensuring full English translation: {text[:50]}...")

        try:
            translation_prompt = """You are a translation expert. The user has dictated text that may contain non-English words.

Your task: Translate EVERYTHING to English. Provide clean, natural English output.

CRITICAL RULES:
1. Translate ALL non-English words to English
2. Keep the meaning and tone accurate
3. Output natural, fluent English
4. Output ONLY the translated text, nothing else
5. If the text is already in English, output it unchanged

Now translate this text to English:"""

            response = self.client.chat.completions.create(
                model=GROQ_CHAT_MODEL,
                messages=[
                    {"role": "system", "content": translation_prompt},
                    {"role": "user", "content": text}
                ],
                temperature=0.1,  # Low temperature for consistent translation
                max_tokens=2048
            )

            translated_text = self._chat_text(response)
            if not translated_text:
                logging.warning("[Transcriber] Translate returned empty; keeping original")
                return text
            logging.info(f"[Transcriber] Translated: {translated_text[:50]}...")

            return translated_text

        except Exception as e:
            logging.error(f"[Transcriber] Translation failed: {e}, returning original text")
            return text

    def _chat_text(self, response) -> str:
        """gpt-oss may put the answer in content, a list of parts, or reasoning."""
        try:
            msg = response.choices[0].message
        except Exception:
            return ""
        content = getattr(msg, "content", None)
        if isinstance(content, str) and content.strip():
            return content.strip()
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, str):
                    parts.append(item)
                elif isinstance(item, dict) and item.get("text"):
                    parts.append(str(item["text"]))
                else:
                    text = getattr(item, "text", None)
                    if text:
                        parts.append(str(text))
            joined = "".join(parts).strip()
            if joined:
                return joined
        for attr in ("reasoning", "reasoning_content"):
            extra = getattr(msg, attr, None)
            if extra and str(extra).strip():
                return str(extra).strip()
        return ""


def main():
    api_key = input("Enter Groq API Key: ").strip()
    if not api_key:
        print("API key is required.")
        return
        
    transcriber = Transcriber(api_key=api_key)
    
    filename = "temp_recording.wav"
    if not os.path.exists(filename):
        print(f"File {filename} not found. Perform a recording first.")
        return
        
    try:
        text = transcriber.transcribe_file(filename)
        print("\nTranscribed Text:")
        print("-" * 20)
        print(text)
        print("-" * 20)
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
