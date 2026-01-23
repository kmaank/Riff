
from groq import Groq
import os
import sys
import logging
import time
import re

class TranscriptionError(Exception):
    pass

class Transcriber:
    # Script mode prompts for Whisper
    # Note: These are hints for Whisper. english_mixed uses post-processing for romanization.
    SCRIPT_MODE_PROMPTS = {
        "english_mixed": "Transcribe the audio naturally, keeping code-switching.",
        "english_translated": "Translate all speech to English.",
        # Use the same prompt as english_mixed because it correctly captures original scripts (e.g. Devanagari)
        # We just skip the romanization step in post-processing.
        "original_mixed": "Transcribe the audio naturally, keeping code-switching."
    }

    def __init__(self, api_key: str, script_mode: str = "english_mixed"):
        if not api_key:
            raise TranscriptionError("API key is required.")
        try:
            self.client = Groq(api_key=api_key, timeout=300.0)
            self.script_mode = script_mode
            logging.info(f"[Transcriber] Init: script_mode={script_mode}")
        except Exception as e:
            raise TranscriptionError(f"Failed to initialize Groq client: {e}")
        
    def transcribe_file(self, filepath: str) -> str:
        if not os.path.exists(filepath):
            logging.error(f"[Transcriber] File not found: {filepath}")
            raise TranscriptionError(f"File not found: {filepath}")

        # Groq API Limit Check (25MB)
        file_size_bytes = os.path.getsize(filepath)
        file_size_mb = file_size_bytes / (1024 * 1024)
        logging.info(f"[Transcriber] Request: {filepath} ({file_size_mb:.2f} MB)")
        
        if file_size_mb > 25:
             logging.error(f"[Transcriber] File too large: {file_size_mb:.2f}MB")
             raise TranscriptionError(f"Audio file too large ({file_size_mb:.1f}MB). Groq limit is 25MB (~13 mins). Please shorten.")
            
        print("[Transcribing...]")
        start_time = time.time()
        try:
            # Get prompt for script mode
            prompt = self.SCRIPT_MODE_PROMPTS.get(self.script_mode, self.SCRIPT_MODE_PROMPTS["english_mixed"])
            logging.info(f"[Transcriber] Using script_mode: {self.script_mode}")

            with open(filepath, "rb") as file:
                # Build API params
                api_params = {
                    "file": (filepath, file.read()),
                    "model": "whisper-large-v3",
                    "response_format": "json",
                    "prompt": prompt
                }

                # For english_translated, set language to English to force translation
                if self.script_mode == "english_translated":
                    api_params["language"] = "en"

                transcription = self.client.audio.transcriptions.create(**api_params)
            
            latency = (time.time() - start_time) * 1000
            logging.info(f"[Transcriber] Success: {len(transcription.text)} chars in {latency:.0f}ms")
            print("[Transcription complete]")
            text = transcription.text.strip()
            logging.info(f"[Transcriber] Whisper Raw Output: {text}")

            # Post-process based on script mode
            text = self._post_process_script_mode(text)

            # Filter Hallucinations (Aggressive)
            # 1. Exact Match List (Common Whisper glitches)
            HALLUCINATIONS_EXACT = [
                "you", "You", "YOU", ".", "..", "...",
                "MBC News", "Amara.org", "Thank you", "Thanks",
                "Subtitles by", "Subtitle by", "aaa aaaa"
            ]
            
            if text in HALLUCINATIONS_EXACT or not text:
                logging.warning(f"[Transcriber] Filtered exact hallucination: '{text}'")
                print(f"[Filtered Hallucination (Exact): '{text}']")
                return ""

            # 2. Regex Patterns (Subtitle credits, bracketed noise)
            
            HALLUCINATION_PATTERNS = [
                 r"\[.*\]",            # [Music], [Silence]
                 r"\(.*\)",            # (Applause)
                 r"^Subtitle.*",       # Subtitle by...
                 r"^Translated by.*",  # Translated by...
                 r"^[0-9]+$",          # Just numbers (often noise)
            ]
            
            for pattern in HALLUCINATION_PATTERNS:
                if re.search(pattern, text, re.IGNORECASE):
                     logging.warning(f"[Transcriber] Filtered regex hallucination: '{text}' (Pattern: {pattern})")
                     print(f"[Filtered Hallucination (Regex): '{text}']")
                     return ""

            return text

        except Exception as e:
            logging.error(f"[Transcriber] Failed: {e}", exc_info=True)
            raise TranscriptionError(f"Transcription failed: {e}")

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
            # No post-processing needed
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
            # Already in Latin script, no need to romanize
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
                model="llama-3.3-70b-versatile",
                messages=[
                    {"role": "system", "content": romanization_prompt},
                    {"role": "user", "content": text}
                ],
                temperature=0.1,  # Low temperature for consistent romanization
                max_tokens=512
            )

            romanized_text = response.choices[0].message.content.strip()
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
                model="llama-3.3-70b-versatile",
                messages=[
                    {"role": "system", "content": translation_prompt},
                    {"role": "user", "content": text}
                ],
                temperature=0.1,  # Low temperature for consistent translation
                max_tokens=512
            )

            translated_text = response.choices[0].message.content.strip()
            logging.info(f"[Transcriber] Translated: {translated_text[:50]}...")

            return translated_text

        except Exception as e:
            logging.error(f"[Transcriber] Translation failed: {e}, returning original text")
            return text

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
