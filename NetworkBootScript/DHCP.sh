#!/bin/bash

help_func(){
cat << EOF
DHCP and TFTP SERVER SETUP PROGRAM

	-R <start of address>,<end of address>,<subnet mask>,<broadcast address> , --range=<user name><start of address>,<end of address>,<subnet mask>,<broadcast address>
		Set IP address range

	-H , --help		Show Help  (This Page)

EOF
}

shift_Flag=0
DHCP_only_Flag=0
# range="10.0.2.0,proxy"
range=""
router_addr=""

while [[ $# -gt 0  ]]
do
	case $1 in
		-[Rr]|-[Rr]=*|--range|--range=*)
			if [[ $1 =~ .+= ]]; then
				echo \$1=$1
				range=$(echo $1 | sed s/.*=//g)
			elif [[ -z $2 ]] || [[ $2 =~ ^- ]]; then
	        	echo "Error!!: One or more argument of $1 are missing ."
				exit 1
			else
				range=$2
				shift_Flag=1
			fi;;
		# -[Rr]|-[Rr]=*|--router|--router=*)
		# 	if [[ $1 =~ .+= ]]; then
		# 		echo \$1=$1
		# 		router_addr=$(echo $1 | sed s/.*=//g)
		# 	elif [[ -z $2 ]] || [[ $2 =~ ^- ]]; then
	    #     	echo "Error!!: One or more argument of $1 are missing ."
		# 		exit 1
		# 	else
		# 		router=$2
		# 		shift_Flag=1
		# 	fi;;
		-[Dd][Oo]|--DHCP_only)
            DHCP_only_Flag=1;;
		-[hH]|--help)
			help_func
			exit 0;;
	    *) 
	        echo "Error!!: $1 is Invalid argument ."
			exit 1;;
	esac
	if [[ shift_Flag -eq 1 ]]; then 
		shift;
		shift_Flag=0;
	fi
shift
done
if [[ -z $range ]];then 
	echo "Argument -U is not specified .";
	exit 1;
fi

dnf -y install dnsmasq

cat <<EOF > /etc/dnsmasq.conf
port=0
user=dnsmasq
group=dnsmasq
interface=*
bind-interfaces
log-queries
log-facility=/var/log/dnsmasq.log
log-debug
conf-dir=/etc/dnsmasq.d,.rpmnew,.rpmsave,.rpmorig
dhcp-boot=BOOTX64.EFI
# dhcp-boot=pxelinux.0
dhcp-range=$range
# pxe-service=x86-64_EFI,"sample-text-A",BOOTX64.EFI
# pxe-service=x86PC,"sample-text-B",pxelinux.0
pxe-prompt="This is PXE server !!"
EOF

if [[ $DHCP_only_Flag -eq 0 ]]; then
    cat <<-EOF >> /etc/dnsmasq.conf
        enable-tftp
        tftp-secure 
        tftp-lowercase
        tftp-root=/home/data/tftp
	EOF

    # SELinux setting
    cat <<-EOF > my-dnsmasq.te
        module my-dnsmasq 1.0;

        require {
            type dnsmasq_t;
            type home_root_t;
            class dir search;
        }

        allow dnsmasq_t home_root_t:dir search;
	EOF

    make -f /usr/share/selinux/devel/Makefile
    semodule -X 300 -i my-dnsmasq.pp
    rm my-dnsmasq.*

    mkdir -p /home/data/tftp
    chmod 777 -R /home/data/tftp

    semanage fcontext --add --type public_content_rw_t "/home/data(/.*)?"
    restorecon -R /home/data
fi

touch /var/log/dnsmasq.log
chmod 660 /var/log/dnsmasq.log
chown dnsmasq:root /var/log/dnsmasq.log

semanage fcontext --add --type dnsmasq_var_log_t "/var/log/dnsmasq.log"
restorecon /var/log/dnsmasq.log

if [[ $DHCP_only_Flag -eq 0 ]]; then
    firewall-cmd  --permanent --add-service=tftp
fi
firewall-cmd  --permanent --add-service=dhcp
firewall-cmd  --reload
systemctl enable --now dnsmasq

cat << EOF > my-snappy-by-dnsmasq.te
module my-snappy-by-dnsmasq 1.0;

require {
        type snappy_t;
        type type public_content_rw_t;
        class dir { getattr open read };
}

allow snappy_t public_content_rw_t:dir { getattr open read };
EOF

make -f /usr/share/selinux/devel/Makefile
semodule -X 300 -i my-snappy-by-dnsmasq.pp
rm my-snappy-by-dnsmasq.*