#!/bin/bash
# Simple test installer

echo "🚀 Test Installer Starting..."
echo "$(date): Test installer started" > /tmp/test_install.log

echo "Phase 1: System check"
echo "$(date): Phase 1 started" >> /tmp/test_install.log

# Stop any Bell News processes
pkill -f "vcns_timer_web.py" 2>/dev/null || true
pkill -f "bellnews" 2>/dev/null || true

echo "Phase 2: Cleanup"
echo "$(date): Phase 2 started" >> /tmp/test_install.log

# Remove old installations
rm -rf /opt/bellnews 2>/dev/null || true
rm -rf /tmp/OnlyBell2025 2>/dev/null || true

echo "Phase 3: Download"
echo "$(date): Phase 3 started" >> /tmp/test_install.log

cd /tmp
git clone https://github.com/EmmanuelMsafiri1992/OnlyBell2025.git

if [ -d "/tmp/OnlyBell2025" ]; then
    echo "✅ Download successful"
    echo "$(date): Download successful" >> /tmp/test_install.log
else
    echo "❌ Download failed"
    echo "$(date): Download failed" >> /tmp/test_install.log
fi

echo "🎉 Test completed successfully!"
echo "$(date): Test completed" >> /tmp/test_install.log