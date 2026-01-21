
import sys
import os
import json
import time
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from utils.config_manager import ConfigManager

def test_atomic_save():
    # Setup
    test_config_path = "tests/test_config.json"
    if os.path.exists(test_config_path):
        os.remove(test_config_path)
        
    cm = ConfigManager(test_config_path)
    
    # Test 1: Save and Verify
    cm.set("test.key", "value1")
    
    with open(test_config_path, 'r') as f:
        data = json.load(f)
        print(f"Test 1 Value: {data.get('test', {}).get('key')}")
        assert data.get('test', {}).get('key') == "value1"
        
    # Test 2: Atomic Property Check (Mocking is hard here without extensive setup, 
    # but we can check if .tmp file is gone)
    cm.set("test.key", "value2")
    
    assert not os.path.exists(test_config_path + ".tmp")
    print("Temp file correctly cleaned up.")
    
    with open(test_config_path, 'r') as f:
        data = json.load(f)
        print(f"Test 2 Value: {data.get('test', {}).get('key')}")
        assert data.get('test', {}).get('key') == "value2"

    # Cleanup
    if os.path.exists(test_config_path):
        os.remove(test_config_path)
    
    print("Atomic Save Test Passed!")

if __name__ == "__main__":
    test_atomic_save()
