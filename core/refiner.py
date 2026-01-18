
from groq import Groq

class RefinementError(Exception):
    pass

class Refiner:
    STYLES = {
        "clean": """You are a dictation editor. Clean the following transcript.
REMOVE: filler words (um, uh, like, you know, basicially), repetitions, and hesitations.
FIX: grammar, punctuation, and capitalization.
KEEP: the original tone, meaning, and non-filler words. 
Do NOT act as a chatbot. Do NOT add intros/outros. Output ONLY the refined text.""",

        "professional": """You are a professional editor. Rewrite the following transcript to be formal and concise.
REMOVE: all filler words, slang, and casual phrasing.
IMPROVE: structure, clarity, and vocabulary.
ENSURE: professional tone suitable for business communication.
Output ONLY the refined text.""",

        "casual": """You are a friendly editor. Clean up the transcript but keep it casual and conversational.
REMOVE: excessive filler words only.
FIX: basic punctuation.
KEEP: slang, emojis (if any), and the speaker's personality.
Output ONLY the refined text."""
    }

    def __init__(self, api_key: str, model: str = "llama-3.3-70b-versatile"):
        self.client = Groq(api_key=api_key)
        self.model = model

    def refine(self, text: str, style: str = "clean", prompt: str = None) -> str:
        if not text:
            return ""
            
        # Use provided prompt if available, otherwise fallback to internal dictionary (mostly for backward compatibility/standalone usage)
        system_prompt = prompt if prompt else self.STYLES.get(style, self.STYLES["clean"])
        
        try:
            chat_completion = self.client.chat.completions.create(
                messages=[
                    {
                        "role": "system",
                        "content": system_prompt,
                    },
                    {
                        "role": "user",
                        "content": f"Transcript: {text}",
                    }
                ],
                model=self.model,
                temperature=0.3, # Low temperature for consistent editing
                max_tokens=1024,
            )
            
            return chat_completion.choices[0].message.content.strip()
            
        except Exception as e:
            raise RefinementError(f"Refinement failed: {e}")

def main():
    api_key = input("Enter Groq API Key: ").strip()
    if not api_key:
        print("API key is required.")
        return

    refiner = Refiner(api_key=api_key)
    
    sample_text = "Um, hi there! I was uh thinking that maybe we should like go to the store or something, you know?"
    print(f"\nOriginal: {sample_text}")
    
    try:
        refined = refiner.refine(sample_text, style="clean")
        print(f"Refined (Clean): {refined}")
        
        refined_pro = refiner.refine(sample_text, style="professional")
        print(f"Refined (Professional): {refined_pro}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
