#!/bin/bash
## Version 001 06/25/208
## Usage: Set uv_nmi action to KDB on SLES VLI servers

if [[ $EUID -ne 0 ]]; then
	echo "Must be run as root"
	exit 1
fi

HPEKDUMP=/usr/local/sbin/hpekdump
SVCNAME=hpekdump.service
SVCFILE=/etc/systemd/system/"$SVCNAME"

usage() {
	echo "Usage: $0 [-u|-s]"
	echo "With no args, checks if KDB activation on serial is set up, and does so if it is not"
	echo "With -u, undoes all changes made when it was run without -u"
	echo "With -s, checks status and prints a message"
	exit 2
}

S="`cat /sys/module/uv_nmi/parameters/action 2>/dev/null || echo ERROR`"
if [[ "$S" == "ERROR" ]]; then
	echo "Error: Cannot access /sys/module/uv_nmi/parameters/action - check that module uv_nmi is loaded"
	exit 101
fi

if [[ "$1" == "-s" ]]; then
	#status
	[[ "$S" == "kdb" ]] && echo "KDB is configured" || echo "KDB is unconfigured"
	exit 0
elif [[ "$1" == "-u" ]]; then
	#unconfigure
	if [[ -e "$SVCFILE" || -e "$HPEKDUMP" || "$S" == "kdb" ]]; then
		echo "Unconfiguring kdb on serial"
		if [[ -e "$SVCFILE" ]]; then
			systemctl stop "$SVCNAME" >/dev/null 2>&1
			systemctl disable "$SVCNAME" >/dev/null 2>&1
			rm -f "$SVCFILE" >/dev/null 2>&1
			systemctl daemon-reload >/dev/null 2>&1
			systemctl reset-failed >/dev/null 2>&1
		fi
		rm -f "$HPEKDUMP"
		> /sys/module/kgdboc/parameters/kgdboc
		echo -n dump > /sys/module/uv_nmi/parameters/action
		exit 0
	else
		echo "kdb on serial is not configured, doing nothing"
		exit 201
	fi
elif [[ -z "$1" ]]; then
	#configure
	if [[ "$S" == "kdb" ]]; then
		echo "KDB is already configured!"
		exit 102
	else
		cat > "$HPEKDUMP" <<EOF
#!/bin/bash

echo ttyS0 > /sys/module/kgdboc/parameters/kgdboc
echo -n kdb > /sys/module/uv_nmi/parameters/action
EOF

		chmod +x "$HPEKDUMP"

		cat > "$SVCFILE" <<EOF
[Unit]
Description=Configures kdb activation over serial port
After=network.target

[Service]
Type=simple
ExecStart=$HPEKDUMP
TimeoutStartSec=0

[Install]
WantedBy=default.target
EOF

		systemctl daemon-reload
		systemctl enable "$SVCNAME"
		systemctl start "$SVCNAME"
		exit 0
	fi
else
	usage
fi


