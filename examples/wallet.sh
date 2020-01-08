#!/bin/bash

examples_dir=$(dirname $(realpath $0))
temp_dir=$(mktemp --directory /tmp/wallet23.XXXXXX)

if [[ -f .mywallet.txt ]]; then
	wallet_address=$(cat .mywallet.txt)
fi

if [[ $wallet_address == "" ]]; then
	clear

	nonce="0"
	read -p "key1 [key1.pk]: " key1_file; key1_file=${key1_file:-"key1.pk"}
	read -p "key2 [key2.pk]: " key2_file; key2_file=${key2_file:-"key2.pk"}
	read -p "key3 [key3.pk]: " key3_file; key3_file=${key3_file:-"key3.pk"}
	read -p "workchain id [0]: " workchain_id; workchain_id=${workchain_id:-0}

	while [[ $wallet_address == "" ]]; do
		clear

		fift -s "$examples_dir/msg-init.fif" \
			"$key1_file" "$key2_file" "$key3_file" "$workchain_id" "$nonce" \
			"$temp_dir/.mywallet.txt" "$temp_dir/.mywallet.boc" \
				|| exit 1

		echo ""
		read -p "try another address? [y/N]: " answer

		if [[ $answer == "y" ]]; then
			nonce=$(($nonce + 1))
		else
			cp "$temp_dir/.mywallet.txt" .mywallet.txt
			cp "$temp_dir/.mywallet.boc" .mywallet.boc
			wallet_address=$(cat .mywallet.txt)
		fi
	done
fi

while [[ ! -f $key_file ]]; do
	ls -1 *.pk | sort | cat -n
	read -p "select private key: " answer
	key_file=$(ls -1 *.pk | sort | sed -ne ${answer}p)
done

wget https://test.ton.org/ton-lite-client-test1.config.json -O "$temp_dir/lite-client.json" || exit 1

while [[ true ]]; do
	output=$(lite-client --global-config "$temp_dir/lite-client.json" \
		-c "last" -c "saveaccountdata $temp_dir/data.boc $wallet_address" 2>&1 | tee /dev/stderr
	) || exit 1

	if echo "$output" | grep -q "account state is empty"; then
		if [[ ! -f .mywallet.boc ]]; then
			>&2 echo ".mywallet.boc not found"
			exit 1
		fi

		echo "send grams to $wallet_address"
		read -p "press [enter] to refresh" < /dev/tty
		continue
	fi

	if echo "$output" | grep -q "account not initialized"; then
		if [[ -f .mywallet.boc ]]; then
			lite-client --global-config "$temp_dir/lite-client.json" -c "sendfile .mywallet.boc" || exit 1;
			rm .mywallet.boc
			echo "init message sent"
		fi

		echo "waiting for init"
		read -p "press [enter] to refresh" < /dev/tty
		continue
	fi

	balance_ng=$(echo "$output" | grep -Po "account balance is [0-9]+ng" | grep -Po "[0-9]+")
	balance=$(echo "scale=3; $balance_ng/1000000000" | bc)

	output=$(fift -s "$examples_dir/print-data.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
		seqno my_request other_request1 other_request1_key other_request2 other_request2_key
	) || exit 1

	seqno=$(echo "$output" | sed -ne 1p)
	my_request=$(echo "$output" | sed -ne 2p)
	other_request1=$(echo "$output" | sed -ne 3p)
	other_request1_key=$(echo "$output" | sed -ne 4p)
	other_request2=$(echo "$output" | sed -ne 5p)
	other_request2_key=$(echo "$output" | sed -ne 6p)

	clear
	echo "address: $wallet_address"
	echo "key:     $key_file"
	echo "balance: GR\$$balance"
	echo "seqno:   $seqno"
	echo ""

	if [[ $my_request != "" ]]; then
		echo "your request:"
		echo "  $my_request"
	fi

	if [[ $other_request1 != "" ]]; then
		echo "confirm1:"
		echo "  $other_request1 (by ${other_request1_key:0:8})"
	fi
	if [[ $other_request2 != "" ]]; then
		echo "confirm2:"
		echo "  $other_request2 (by ${other_request2_key:0:8})"
	fi
	if [[ $my_request == "" && ($other_request1 != "" || $other_request2 != "") ]]; then
		echo "cancel:"
		echo "  create new cancellation request"
	fi
	if [[ $my_request == "" ]]; then
		echo "transfer:"
		echo "  create new simple transfer request"
	fi
	if [[ $my_request == "" ]]; then
		echo "replace-key:"
		echo "  create new request replacing your public key"
	fi

	echo ""
	read -p "command [refresh]: " answer < /dev/tty

	if [[ $answer == "confirm1" && $other_request1 != "" ]]; then
		fift -s "$examples_dir/msg-confirmation.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
			"other_request1" "$temp_dir/msg_confirmation1.boc" || exit 1

		lite-client --global-config "$temp_dir/lite-client.json" \
			-c "last" -c "sendfile $temp_dir/msg_confirmation1.boc" || exit 1;

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "confirm2" && $other_request2 != "" ]]; then
		fift -s "$examples_dir/msg-confirmation.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
			"other_request2" "$temp_dir/msg_confirmation2.boc" || exit 1

		lite-client --global-config "$temp_dir/lite-client.json" \
			-c "last" -c "sendfile $temp_dir/msg_confirmation2.boc" || exit 1;

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "cancel" ]]; then
		read -p "comment: " comment < /dev/tty

		fift -s "$examples_dir/msg-cancellation.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
			"$comment" "$temp_dir/msg_cancellation.boc" || exit 1

		lite-client --global-config "$temp_dir/lite-client.json" \
			-c "last" -c "sendfile $temp_dir/msg_cancellation.boc" || exit 1;

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "transfer" && $my_request == "" ]]; then
		read -p "destination address: " destination_address < /dev/tty
		read -p "amount: " amount < /dev/tty
		read -p "comment: " comment < /dev/tty

		fift -s "$examples_dir/msg-simple-transfer.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
			"$destination_address" "$amount" "$comment" "$temp_dir/msg_simple_transfer.boc" || exit 1

		lite-client --global-config "$temp_dir/lite-client.json" \
			-c "last" -c "sendfile $temp_dir/msg_simple_transfer.boc" || exit 1;

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "replace-key" && $my_request == "" ]]; then
		read -p "new private key file: " new_key_file < /dev/tty

		fift -s "$examples_dir/msg-replace-key.fif" "$wallet_address" "$temp_dir/data.boc" "$key_file" \
			"$new_key_file" "$temp_dir/msg_replace_key.boc" || exit 1

		lite-client --global-config "$temp_dir/lite-client.json" \
			-c "last" -c "sendfile $temp_dir/msg_replace_key.boc" || exit 1;

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi
done
