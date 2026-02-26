"""
Tests for AuthManager
Unit tests with mocked HTTP responses
"""

import pytest
import json
from unittest.mock import Mock, patch, MagicMock
from utils.auth_manager import AuthManager
from utils.config_manager import ConfigManager


@pytest.fixture
def mock_config():
    """Create a mock ConfigManager."""
    config = Mock(spec=ConfigManager)
    config.get.side_effect = lambda key, default=None: {
        "auth.supabase_url": "https://test-project.supabase.co",
        "auth.supabase_anon_key": "test-anon-key",
        "api.api_key": "test-groq-key",
    }.get(key, default)
    config.config_path = "/tmp/test_config.json"
    return config


@pytest.fixture
def auth_manager(mock_config):
    """Create AuthManager with mocked config."""
    with patch('utils.auth_manager.httpx.Client'):
        with patch('utils.auth_manager.keyring'):
            manager = AuthManager(mock_config)
            return manager


def test_init(auth_manager):
    """Test AuthManager initialization."""
    assert auth_manager.supabase_url == "https://test-project.supabase.co"
    assert auth_manager.supabase_anon_key == "test-anon-key"


def test_login_success(auth_manager):
    """Test successful login."""
    # Mock HTTP response
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "access_token": "test-access-token",
        "refresh_token": "test-refresh-token",
        "user": {"id": "test-user-id", "email": "test@example.com"}
    }

    with patch.object(auth_manager.client, 'post', return_value=mock_response):
        with patch.object(auth_manager, '_store_tokens'):
            success, message = auth_manager.login("test@example.com", "password123")

    assert success is True
    assert "successful" in message.lower()


def test_login_failure(auth_manager):
    """Test failed login."""
    # Mock HTTP response
    mock_response = Mock()
    mock_response.status_code = 401
    mock_response.json.return_value = {
        "error_description": "Invalid credentials"
    }

    with patch.object(auth_manager.client, 'post', return_value=mock_response):
        success, message = auth_manager.login("test@example.com", "wrongpassword")

    assert success is False
    assert "Invalid credentials" in message


def test_can_riff_not_authenticated(auth_manager):
    """Test can_riff when not authenticated."""
    with patch.object(auth_manager, 'is_authenticated', False):
        allowed, reason = auth_manager.can_riff()

    assert allowed is False
    assert "Not authenticated" in reason


def test_can_riff_quota_exceeded(auth_manager):
    """Test can_riff when quota is exceeded."""
    with patch.object(auth_manager, 'is_authenticated', True):
        with patch.object(auth_manager, 'validate_subscription') as mock_validate:
            mock_validate.return_value = {
                "valid": False,
                "tier": "free",
                "status": "active",
                "quota": {
                    "riffs_limit": 100,
                    "riffs_used": 100,
                    "seconds_limit": None,
                    "seconds_used": 0,
                }
            }
            allowed, reason = auth_manager.can_riff()

    assert allowed is False


def test_can_riff_allowed(auth_manager):
    """Test can_riff when user is allowed."""
    with patch.object(auth_manager, 'is_authenticated', True):
        with patch.object(auth_manager, 'validate_subscription') as mock_validate:
            mock_validate.return_value = {
                "valid": True,
                "tier": "pro",
                "status": "active",
                "quota": {
                    "riffs_limit": None,
                    "riffs_used": 50,
                    "seconds_limit": None,
                    "seconds_used": 1000,
                }
            }
            allowed, reason = auth_manager.can_riff()

    assert allowed is True
    assert reason == ""


def test_get_effective_api_key_byok(auth_manager, mock_config):
    """Test get_effective_api_key for BYOK tier."""
    with patch.object(auth_manager, 'get_tier', return_value='free'):
        api_key = auth_manager.get_effective_api_key()

    assert api_key == "test-groq-key"  # From config


def test_get_effective_api_key_managed(auth_manager):
    """Test get_effective_api_key for managed tier."""
    with patch.object(auth_manager, 'get_tier', return_value='pro'):
        api_key = auth_manager.get_effective_api_key()

    assert api_key is None  # Proxy mode


def test_should_use_proxy(auth_manager):
    """Test should_use_proxy for different tiers."""
    # Free tier - should NOT use proxy
    with patch.object(auth_manager, 'get_tier', return_value='free'):
        assert auth_manager.should_use_proxy() is False

    # Pro tier - should use proxy
    with patch.object(auth_manager, 'get_tier', return_value='pro'):
        assert auth_manager.should_use_proxy() is True


def test_log_usage_success(auth_manager):
    """Test successful usage logging."""
    mock_response = Mock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "success": True,
        "quota": {
            "riffs_used": 51,
            "seconds_used": 1010.5
        }
    }

    with patch.object(auth_manager, '_get_access_token', return_value='test-token'):
        with patch.object(auth_manager, 'user_id', 'test-user-id'):
            with patch.object(auth_manager.client, 'post', return_value=mock_response):
                result = auth_manager.log_usage(100, 10.5, "casual", "english_mixed")

    assert result is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
