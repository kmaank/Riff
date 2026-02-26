"""
HMAC Request Signing
Prevents patched client abuse by signing sensitive API requests
"""

import hmac
import hashlib
import time
from typing import Tuple


def sign_request(user_id: str, endpoint: str, access_token: str, hmac_secret: str = None) -> str:
    """
    Sign a request with HMAC-SHA256.

    Args:
        user_id: User's UUID
        endpoint: API endpoint being called (e.g., "/log-usage")
        access_token: JWT access token
        hmac_secret: HMAC secret (optional, for custom secret)

    Returns:
        Signature string in format "timestamp:signature"
    """
    timestamp = int(time.time())
    message = f"{user_id}:{endpoint}:{timestamp}"

    # Use access token as HMAC key (shared secret with server)
    # Server can verify using the same token
    key = (hmac_secret or access_token).encode('utf-8')
    message_bytes = message.encode('utf-8')

    signature = hmac.new(key, message_bytes, hashlib.sha256).hexdigest()

    return f"{timestamp}:{signature}"


def verify_signature(
    signature: str,
    user_id: str,
    endpoint: str,
    access_token: str,
    max_age: int = 300,  # 5 minutes
    hmac_secret: str = None
) -> Tuple[bool, str]:
    """
    Verify a request signature (for testing purposes).

    Args:
        signature: Signature string from sign_request()
        user_id: User's UUID
        endpoint: API endpoint
        access_token: JWT access token
        max_age: Maximum age of signature in seconds
        hmac_secret: HMAC secret (optional)

    Returns:
        (valid: bool, error: str)
    """
    try:
        timestamp_str, client_signature = signature.split(":")
        timestamp = int(timestamp_str)
    except (ValueError, AttributeError):
        return False, "Invalid signature format"

    # Check timestamp age
    now = int(time.time())
    if abs(now - timestamp) > max_age:
        return False, f"Signature expired (max age: {max_age}s)"

    # Recreate signature
    message = f"{user_id}:{endpoint}:{timestamp}"
    key = (hmac_secret or access_token).encode('utf-8')
    message_bytes = message.encode('utf-8')

    expected_signature = hmac.new(key, message_bytes, hashlib.sha256).hexdigest()

    # Constant-time comparison
    if hmac.compare_digest(expected_signature, client_signature):
        return True, ""
    else:
        return False, "Signature mismatch"


def create_signed_headers(
    user_id: str,
    endpoint: str,
    access_token: str,
    hmac_secret: str = None
) -> dict:
    """
    Create headers with both Authorization and X-Request-Signature.

    Args:
        user_id: User's UUID
        endpoint: API endpoint being called
        access_token: JWT access token
        hmac_secret: Optional HMAC secret

    Returns:
        Dictionary of headers to include in request
    """
    signature = sign_request(user_id, endpoint, access_token, hmac_secret)

    return {
        "Authorization": f"Bearer {access_token}",
        "X-Request-Signature": signature,
        "Content-Type": "application/json",
    }


if __name__ == "__main__":
    # Test signing
    test_user_id = "12345678-1234-1234-1234-123456789abc"
    test_endpoint = "/log-usage"
    test_token = "test_access_token_here"

    # Sign request
    signature = sign_request(test_user_id, test_endpoint, test_token)
    print(f"Signature: {signature}")

    # Verify immediately (should succeed)
    valid, error = verify_signature(signature, test_user_id, test_endpoint, test_token)
    print(f"Valid: {valid}, Error: {error}")

    # Test with wrong user_id (should fail)
    valid, error = verify_signature(signature, "wrong-user-id", test_endpoint, test_token)
    print(f"Wrong user_id - Valid: {valid}, Error: {error}")

    # Test with wrong endpoint (should fail)
    valid, error = verify_signature(signature, test_user_id, "/wrong-endpoint", test_token)
    print(f"Wrong endpoint - Valid: {valid}, Error: {error}")

    # Test headers
    headers = create_signed_headers(test_user_id, test_endpoint, test_token)
    print(f"\nHeaders:\n{headers}")
