#For some reason this only work when contained in another script
DISTRO=$( (lsb_release -ds || cat /etc/*release || uname -om) 2>/dev/null | head -n1)
echo "$DISTRO"
