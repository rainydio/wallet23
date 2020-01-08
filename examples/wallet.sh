#!/bin/bash

format_request() {
	sed 's/ | /\n/g' | sed 's/^ *//' | fold -w 80 -s | sed 's/^/  /'
}

examples=$(dirname $(realpath $0))
temp=$(mktemp --directory /tmp/wallet23.XXX) || exit 1

trap "{ rm -rf $temp; }" EXIT

if [[ $1 != *.pk ]]; then wallet_address="$1"; fi
if [[ $1 == *.pk && -f $1 ]]; then key_file="$1"; fi
if [[ $2 == *.pk && -f $2 ]]; then key_file="$2"; fi

if [[ $wallet_address == "" && -f .mywallet.txt ]]; then
	wallet_address=$(cat .mywallet.txt)
fi

if [[ $wallet_address == "" ]]; then
	clear

	echo "$0 [wallet address] [key file]"
	echo "  no wallet address provided and no .mywallet.txt found"
	echo "  new wallet address (non-bounceable) will be saved into .mywallet.txt"
	echo ""

	read -p "key1 [key1.pk]: " key1_file; key1_file=${key1_file:-"key1.pk"}
	read -p "key2 [key2.pk]: " key2_file; key2_file=${key2_file:-"key2.pk"}
	read -p "key3 [key3.pk]: " key3_file; key3_file=${key3_file:-"key3.pk"}
	read -p "workchain id [0]: " workchain_id; workchain_id=${workchain_id:-0}
	read -p "nonce [0]: " nonce; nonce=${nonce:-0}

	while [[ $wallet_address == "" ]]; do
		clear

		fift -s "$examples/msg-init.fif" \
			"$key1_file" "$key2_file" "$key3_file" "$workchain_id" "$nonce" \
			"$temp/.mywallet.txt" "$temp/.mywallet.boc" || exit 1

		echo ""
		read -p "try another address? [y/N]: " answer

		if [[ $answer == "y" ]]; then
			read -p "nonce [$(($nonce + 1))]: " answer; nonce=${answer:-$(($nonce + 1))}
		else
			cp "$temp/.mywallet.txt" .
			cp "$temp/.mywallet.boc" .
			wallet_address=$(cat .mywallet.txt)
		fi
	done
fi

while [[ ! -f $key_file ]]; do
	ls -1 *.pk | sort | cat -n | sed 's/\t/ /' | sed 's/^ *//'
	read -p "select private key: " answer
	key_file=$(ls -1 *.pk | sort | sed -ne ${answer}p)
done

wget https://test.ton.org/ton-lite-client-test1.config.json \
	-O "$temp/lite-client.json" || exit 1

while [[ true ]]; do
	output=$(lite-client -C "$temp/lite-client.json" \
		-c "last" -c "saveaccountdata $temp/data.boc $wallet_address" 2>&1 | tee /dev/stderr
	) || exit 1

	if echo "$output" | grep -q "account state is empty"; then
		if [[ ! -f .mywallet.boc ]]; then
			>&2 echo ".mywallet.boc not found"
			exit 1
		fi

		echo "send grams to $wallet_address"
		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if echo "$output" | grep -q "account not initialized"; then
		if [[ -f .mywallet.boc ]]; then
			lite-client -C "$temp/lite-client.json" -c "sendfile .mywallet.boc" || exit 1;
			mv .mywallet.boc .mywallet.boc.bak
			echo "init message sent"
		fi

		echo "waiting for init"
		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	rm -f .mywallet.boc.bak

	balance_ng=$(echo "$output" | grep -Po "account balance is [0-9]+ng" | grep -Po "[0-9]+")
	balance=$(echo "scale=3; $balance_ng/1000000000" | bc)

	output=$(fift -s "$examples/print-data.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
		seqno \
		my_request \
		other_request1 \
		other_request1_key \
		other_request2 \
		other_request2_key
	) || exit 1

	seqno=$(echo "$output" | sed -ne 1p)
	my_request=$(echo "$output" | sed -ne 2p)
	other_request1=$(echo "$output" | sed -ne 3p)
	other_request1_key=$(echo "$output" | sed -ne 4p)
	other_request2=$(echo "$output" | sed -ne 5p)
	other_request2_key=$(echo "$output" | sed -ne 6p)

	clear
	echo "temp:    $temp"
	echo "key:     $key_file"
	echo "address: $wallet_address"
	echo "balance: GR\$$balance"
	echo "seqno:   $seqno"
	echo ""

	if [[ $my_request != "" ]]; then
		echo "my request:"
		echo "$my_request" | format_request

		if [[ $other_request1 != "" ]]; then
			echo ""
		fi
	fi

	if [[ $other_request1 != "" ]]; then
		echo "confirm1:"
		echo "$other_request1" | format_request
		echo "   - by ${other_request1_key:0:8}"
		echo ""
	fi
	if [[ $other_request2 != "" ]]; then
		echo "confirm2:"
		echo "$other_request2" | format_request
		echo "   - by ${other_request2_key:0:8}"
		echo ""
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
		fift -s "$examples/msg-confirmation.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
			"other_request1" "$temp/msg_confirmation1.boc" || exit 1

		lite-client -C "$temp/lite-client.json" \
			-c "sendfile $temp/msg_confirmation1.boc" || exit 1

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "confirm2" && $other_request2 != "" ]]; then
		fift -s "$examples/msg-confirmation.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
			"other_request2" "$temp/msg_confirmation2.boc" || exit 1

		lite-client -C "$temp/lite-client.json" \
			-c "sendfile $temp/msg_confirmation2.boc" || exit 1

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "cancel" ]]; then
		read -p "comment: " comment < /dev/tty

		fift -s "$examples/msg-cancellation.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
			"$comment" "$temp/msg_cancellation.boc" || exit 1

		lite-client -C "$temp/lite-client.json" \
			-c "sendfile $temp/msg_cancellation.boc" || exit 1

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "transfer" && $my_request == "" ]]; then
		read -p "destination address: " destination_address < /dev/tty
		read -p "amount: " amount < /dev/tty
		read -p "comment: " comment < /dev/tty

		fift -s "$examples/msg-simple-transfer.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
			"$destination_address" "$amount" "$comment" "$temp/msg_simple_transfer.boc" || exit 1

		lite-client -C "$temp/lite-client.json" \
			-c "sendfile $temp/msg_simple_transfer.boc" || exit 1

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi

	if [[ $answer == "replace-key" && $my_request == "" ]]; then
		read -p "new private key file: " new_key_file < /dev/tty

		fift -s "$examples/msg-replace-key.fif" "$wallet_address" "$temp/data.boc" "$key_file" \
			"$new_key_file" "$temp/msg_replace_key.boc" || exit 1

		lite-client -C "$temp/lite-client.json" \
			-c "sendfile $temp/msg_replace_key.boc" || exit 1

		read -p "press [enter] to refresh" < /dev/tty; continue
	fi
done
