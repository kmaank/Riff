
from groq import Groq
import os
import sys

class TranscriptionError(Exception):
    pass

class Transcriber:
    def __init__(self, api_key: str):
        if not api_key:
            raise TranscriptionError("API key is required.")
        try:
            self.client = Groq(api_key=api_key, timeout=20.0)
        except Exception as e:
            raise TranscriptionError(f"Failed to initialize Groq client: {e}")
        
    def transcribe_file(self, filepath: str) -> str:
        if not os.path.exists(filepath):
            raise TranscriptionError(f"File not found: {filepath}")
            
        print("[Transcribing...]")
        try:
            with open(filepath, "rb") as file:
                transcription = self.client.audio.transcriptions.create(
                    file=(filepath, file.read()),
                    model="whisper-large-v3",
                    response_format="json"
                )
            
            print("[Transcription complete]")
            text = transcription.text.strip()
            
            # Filter Hallucinations
            # Whisper known to output these on silence
            HALLUCINATIONS = [
                "you", "You", "YOU",
                "MBC News", "Amara.org",
                "Subtitles by", "Subtitle by",
                ".", ".." 
            ]
            
            if text in HALLUCINATIONS or not text:
                print(f"[Filtered Hallucination: '{text}']")
                return ""
                
            return text
            
        except Exception as e:
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
