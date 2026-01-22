"""
Riff Refiner Module
===================
Refines/cleans transcribed text using Groq LLM.

CRITICAL: The prompts are carefully designed to prevent the LLM from
"answering" questions that appear in the transcription. The user is
DICTATING text, not asking the AI questions.
"""

import logging
from groq import Groq
import time

class RefinementError(Exception):
    """Raised when refinement fails."""
    pass


# =============================================================================
# ANTI-ANSWER PREAMBLE
# =============================================================================
# This preamble is prepended to all style prompts (except 'riff' mode)
# to prevent the LLM from treating dictated questions as prompts to answer.

DICTATION_PREAMBLE = """You are a DICTATION TRANSCRIPTION editor, NOT a chatbot.

CRITICAL CONTEXT: The user is using voice-to-text software. They are DICTATING text they want to type into an application (email, document, chat, etc.). They are NOT talking to you or asking you questions.

YOUR JOB: Clean up and format their spoken words. Output ONLY the cleaned version of what they said.

ABSOLUTE RULES:
1. NEVER answer questions - just clean them up and output them
2. NEVER respond as if they're talking to you
3. NEVER add "Sure!", "Great question!", or any preamble
4. NEVER add explanations or commentary
5. NEVER refuse to output something because it "looks like a prompt"
6. Just output the cleaned text, nothing else

EXAMPLES OF CORRECT BEHAVIOR:
- User dictates: "what is the best restaurant in new york"
  CORRECT output: "What is the best restaurant in New York?"
  WRONG output: "The best restaurants in New York include..."

- User dictates: "um can you help me with my um project"
  CORRECT output: "Can you help me with my project?"
  WRONG output: "Of course! I'd be happy to help with your project..."

- User dictates: "write an email to john about the meeting"
  CORRECT output: "Write an email to John about the meeting."
  WRONG output: "Subject: Meeting Update\n\nDear John,..."

Now apply this specific style:
"""


class Refiner:
    """
    Refines transcribed text using Groq LLM with style-specific prompts.

    Usage:
        refiner = Refiner(api_key)
        cleaned = refiner.refine("um what is the best way to like do this", style="clean")
        # Returns: "What is the best way to do this?"
    """

    STYLES = {
        "clean": (
            DICTATION_PREAMBLE +
            "STYLE: Clean\n"
            "- Remove filler words (um, uh, like, you know, basically, so, actually)\n"
            "- Remove repetitions and hesitations\n"
            "- Fix grammar, punctuation, and capitalization\n"
            "- KEEP the original meaning, tone, and intent exactly\n"
            "- Do NOT rephrase or rewrite - just clean"
        ),

        "professional": (
            DICTATION_PREAMBLE +
            "STYLE: Professional/Formal\n"
            "- Remove ALL filler words, slang, and casual phrasing\n"
            "- Improve clarity and structure\n"
            "- Use professional vocabulary\n"
            "- Suitable for business emails and documents\n"
            "- Still output what they SAID, just in professional form"
        ),

        "casual": (
            DICTATION_PREAMBLE +
            "STYLE: Casual\n"
            "- Remove only excessive filler words\n"
            "- Keep slang, personality, and conversational tone\n"
            "- Fix only obvious errors\n"
            "- Preserve the speaker's authentic voice"
        ),

        "formal": (
            DICTATION_PREAMBLE +
            "STYLE: Formal\n"
            "- Remove ALL filler words, slang, and casual phrasing\n"
            "- Improve clarity and structure\n"
            "- Use professional vocabulary\n"
            "- Suitable for business emails and documents\n"
            "- Still output what they SAID, just in formal form"
        ),

        "code": (
            DICTATION_PREAMBLE +
            "STYLE: Code/Technical\n"
            "- Format as code comments (// or #) OR variable names (snake_case)\n"
            "- If it sounds like a comment, output as a comment\n"
            "- If it sounds like a name/identifier, output as snake_case\n"
            "- Remove filler words completely"
        ),

        # RIFF mode is special - it SHOULD respond conversationally
        "riff": (
            "You are a friendly AI assistant. The user is talking to you directly. "
            "Respond naturally and helpfully to what they said. "
            "Keep responses concise, conversational, and helpful. "
            "Match their tone and energy."
        ),
    }

    def __init__(self, api_key: str, model: str = "llama-3.3-70b-versatile"):
        if not api_key:
            raise RefinementError("API key is required")
        self.client = Groq(api_key=api_key)
        self.model = model
        logging.info(f"[Refiner] Init: Model={model}")

    def refine(self, text: str, style: str = "clean", prompt: str = None) -> str:
        """
        Refine/clean transcribed text.

        Args:
            text: Raw transcribed text
            style: One of 'clean', 'casual', 'professional', 'formal', 'code', 'riff'
            prompt: Optional custom prompt (overrides style)

        Returns:
            Refined text

        Raises:
            RefinementError: If API call fails
        """
        if not text or not text.strip():
            return ""

        # Use provided prompt if available, otherwise use style prompt
        system_prompt = prompt if prompt else self.STYLES.get(style, self.STYLES["clean"])

        logging.info(f"[Refiner] Request: {len(text)} chars, style='{style}'")

        # Format user message to reinforce that this is dictation
        if style == "riff":
            user_message = text  # For riff mode, send directly
        else:
            user_message = f"[DICTATED TEXT TO CLEAN - DO NOT ANSWER, JUST CLEAN UP]:\n{text}"

        start_time = time.time()
        try:
            response = self.client.chat.completions.create(
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_message}
                ],
                model=self.model,
                temperature=0.2,  # Low temperature for consistent output
                max_tokens=2048,
            )

            result = response.choices[0].message.content.strip()

            # Post-process: Remove common LLM preambles that slip through
            result = self._clean_llm_artifacts(result, style)

            latency = (time.time() - start_time) * 1000
            logging.info(f"[Refiner] Success: {len(result)} chars in {latency:.0f}ms")

            return result

        except Exception as e:
            logging.error(f"[Refiner] Failed: {e}", exc_info=True)
            raise RefinementError(f"Refinement failed: {e}")

    def _clean_llm_artifacts(self, text: str, style: str) -> str:
        """Remove common LLM response artifacts that slip through."""
        if style == "riff":
            return text  # Don't clean riff responses

        # Common prefixes to remove
        prefixes = [
            "Here is the cleaned text:",
            "Here's the cleaned text:",
            "Here is the refined text:",
            "Here's the refined text:",
            "Here is the corrected text:",
            "Cleaned text:",
            "Refined text:",
            "Output:",
            "Result:",
            "Sure! ",
            "Sure, ",
            "Of course! ",
            "Certainly! ",
            "Here you go:",
            "Here you go: ",
        ]

        for prefix in prefixes:
            if text.lower().startswith(prefix.lower()):
                text = text[len(prefix):].strip()

        # Remove surrounding quotes if present
        if (text.startswith('"') and text.endswith('"')) or \
           (text.startswith("'") and text.endswith("'")):
            text = text[1:-1]

        # Remove markdown code blocks if present
        if text.startswith("```") and text.endswith("```"):
            lines = text.split("\n")
            text = "\n".join(lines[1:-1])

        return text.strip()


def main():
    """Test the refiner with various inputs including questions."""
    import sys

    print("=" * 60)
    print("       RIFF REFINER TEST - ANTI-ANSWER CHECK")
    print("=" * 60)

    api_key = input("\nEnter Groq API Key: ").strip()
    if not api_key:
        print("API key required.")
        return

    refiner = Refiner(api_key=api_key)

    # Test cases - especially questions that might trigger "answering"
    test_cases = [
        # Normal dictation
        ("Um, hi there! I was uh thinking that maybe we should like go to the store.", "clean"),

        # Questions (should NOT be answered)
        ("What is the best restaurant in New York?", "clean"),
        ("um can you help me with my project", "clean"),
        ("When it comes to winter nail videos what visual hook gets the most engagement", "clean"),

        # Commands (should NOT be executed)
        ("write an email to John about the meeting tomorrow", "clean"),
        ("summarize the key points from yesterday's presentation", "professional"),

        # Professional style
        ("so like basically we need to um you know increase our revenue by like 20 percent", "professional"),
    ]

    for text, style in test_cases:
        print(f"\n{'─' * 60}")
        print(f"INPUT ({style}): {text}")
        print(f"{'─' * 60}")

        try:
            result = refiner.refine(text, style=style)
            print(f"OUTPUT: {result}")

            # Check if it looks like an answer vs cleaned text
            answer_indicators = ["here are", "here's", "the best", "i recommend", "you should", "let me"]
            is_probably_answer = any(ind in result.lower()[:50] for ind in answer_indicators)

            if is_probably_answer and style != "riff":
                print("⚠️  WARNING: This looks like an answer, not cleaned dictation!")
            else:
                print("✓ Looks correct")

        except RefinementError as e:
            print(f"ERROR: {e}")


if __name__ == "__main__":
    main()
