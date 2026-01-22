
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
    SCRIPT_MODE_PROMPTS = {
        "english_mixed": "Transcribe the audio. If non-English words are spoken, romanize them (e.g., 'Mujhe lagta hai' not 'मुझे लगता है'). Keep code-switching natural.",
        "english_translated": "Transcribe and translate all audio to English. If non-English words are spoken, translate them to English.",
        "original_mixed": "Transcribe the audio preserving original scripts (Devanagari, Arabic, etc.). Keep code-switching with original scripts."
    }

    def __init__(self, api_key: str, script_mode: str = "english_mixed"):
        if not api_key:
            raise TranscriptionError("API key is required.")
        try:
            self.client = Groq(api_key=api_key, timeout=300.0)
            self.script_mode = script_mode
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
