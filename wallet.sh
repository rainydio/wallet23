#!/bin/bash

if [[ $# -ne 1 ]]; then
	>&2 echo "$0 <wallet directory>"
	exit 100
fi

if [[ ! -d $1 ]]; then
	mkdir $1
fi

(
	cd $1

	if [[ ! -f ton-global.config ]]; then
		wget https://test.ton.org/ton-lite-client-test1.config.json -O ton-global.config || exit 1
	fi

	if [[ ! -f contract-address.addr ]]; then
		clear
		read -p "enter workchain id: " workchain_id
		nonce="-1"

		while [[ ! -f contract-address.addr ]]; do
			clear
			nonce=$(($nonce + 1))
			fift -s ../msg-init.fif $workchain_id $nonce || exit 1
			read -p "try another address? [y/N]: " answer
			if [[ $answer == "y" ]]; then
				rm contract-address.addr
			fi
		done
	fi

	output=$(fift -s ../print-contract-address.fif) || exit 1
	address_hex=$(echo "$output" | sed -ne 1p)
	address_bounceable=$(echo "$output" | sed -ne 2p)
	address_non_bounceable=$(echo "$output" | sed -ne 3p)

	while [[ true ]]; do
		output=$(lite-client \
			-c "last" \
			-c "saveaccountdata contract-data.boc $address_hex" \
			2>&1 | tee /dev/stderr
		) || exit 1

		if echo "$output" | grep -q "account state is empty"; then
			echo "send grams to $address_non_bounceable"
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi

		if echo "$output" | grep -q "account not initialized"; then
			if [ -f msg-init.boc ]; then
				lite-client -c "sendfile msg-init.boc" || exit 1;
				rm msg-init.boc
				echo "init message sent"
			fi
			echo "waiting for init"
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi

		while [[ true ]]; do
			if [[ -f $key_file ]]; then
				my_key=$(fift -s ../print-public-key.fif "$key_file")
				if fift -s ../print-contract-data.fif keys | grep -q "$my_key"; then
					break
				fi
				echo "access denined"
				echo ""
			else
				clear
			fi

			ls -1 *.pk | sort | cat -n
			read -p "select private key: " answer < /dev/tty
			key_file=$(ls -1 *.pk | sort | sed -ne ${answer}p)
		done

		balance_ng=$(echo "$output" | grep -Po "account balance is [0-9]+ng" | grep -Po "[0-9]+")
		balance=$(echo "scale=3; $balance_ng/1000000000" | bc)

		seqno=$(              fift -s ../print-contract-data.fif seqno                         ) || exit 1
		my_request=$(         fift -s ../print-contract-data.fif my_request         "$key_file") || exit 1
		other_request1=$(     fift -s ../print-contract-data.fif other_request1     "$key_file") || exit 1
		other_request1_key=$( fift -s ../print-contract-data.fif other_request1_key "$key_file") || exit 1
		other_request2=$(     fift -s ../print-contract-data.fif other_request2     "$key_file") || exit 1
		other_request2_key=$( fift -s ../print-contract-data.fif other_request2_key "$key_file") || exit 1

		my_key_short=$(             echo "${my_key:0:8}"             | tr "[:upper:]" "[:lower:]")
		other_request1_key_short=$( echo "${other_request1_key:0:8}" | tr "[:upper:]" "[:lower:]")
		other_request2_key_short=$( echo "${other_request2_key:0:8}" | tr "[:upper:]" "[:lower:]")

		clear
		echo "key:             $my_key_short ($key_file)"
		echo "address:         $address_hex"
		echo "bounceable:      $address_bounceable"
		echo "non-bounceable:  $address_non_bounceable"
		echo "balance:         GR\$$balance"
		echo "seqno:           $seqno"
		echo ""

		if [[ $my_request != "" ]]; then
			echo "your request (waiting confirmation):"
			echo "  $my_request"
			echo ""
		fi

		if [[ $other_request1 != "" ]]; then
			echo "confirm1"
			echo "  $other_request1 (by $other_request1_key_short)"
		fi
		if [[ $other_request2 != "" ]]; then
			echo "confirm2"
			echo "  $other_request2 (by $other_request2_key_short)"
		fi
		if [[ $my_request == "" && ($other_request1 != "" || $other_request2 != "") ]]; then
			echo "cancel"
			echo "  send cancellation request"
		fi
		if [[ $my_request == "" ]]; then
			echo "transfer"
			echo "  send new simple transfer request"
		fi
		if [[ $my_request == "" ]]; then
			echo "replace-key"
			echo "  replace public key"
		fi

		echo ""
	 	read -p "command [refresh]: " answer < /dev/tty

		if [[ $answer == "cancel" ]]; then
			read -p "comment: " comment < /dev/tty

			fift -s ../msg-cancellation.fif "$key_file" "$comment" || exit 1;
			lite-client -c "sendfile msg-cancellation.boc" || exit 1;
			rm msg-cancellation.boc
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi

		if [[ $answer == "confirm1" && $other_request1 != "" ]]; then
			fift -s ../msg-confirmation.fif "$key_file" other_request1 || exit 1;
			lite-client -c "sendfile msg-confirmation.boc" || exit 1;
			rm msg-confirmation.boc
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi

		if [[ $answer == "confirm2" && $other_request1 != "" ]]; then
			fift -s ../msg-confirmation.fif "$key_file" other_request2 || exit 1;
			lite-client -c "sendfile msg-confirmation.boc" || exit 1;
			rm msg-confirmation.boc
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi

		if [[ $answer == "transfer" && $my_request == "" ]]; then
			read -p "destination address: " destination_address < /dev/tty
			read -p "amount: " amount < /dev/tty
			read -p "comment: " comment < /dev/tty

			fift -s ../msg-simple-transfer.fif "$key_file" \
				"$destination_address" "$amount" "$comment" || exit 1

			lite-client -c "sendfile msg-simple-transfer.boc" || exit 1;
			rm msg-simple-transfer.boc
			read -p "press [enter] to refresh" < /dev/tty

			continue
		fi

		if [[ $answer == "replace-key" && $my_request == "" ]]; then
			read -p "new private key file: " new_key_file < /dev/tty

			fift -s ../msg-replace-key.fif "$key_file" "$new_key_file" || exit 1;
			lite-client -c "sendfile msg-replace-key.boc" || exit 1;
			rm msg-replace-key.boc
			read -p "press [enter] to refresh" < /dev/tty
			continue
		fi
	done
) || exit 1
