#!/bin/bash

if [ ! -f "ton-global.config" ]; then
	clear
	echo -n "Download lite-client config for test-net? [y/n]: "; read download_lite_client_config
	if [ $download_lite_client_config == "y" ]; then
		if ! wget https://test.ton.org/ton-lite-client-test1.config.json -O ton-global.config; then
			exit 1
		fi
	fi
fi

if [ ! -f "ton-global.config" ]; then
	clear
	echo "ton-global.config not found"
	exit 1
fi

if [ ! -f "wallet-address.txt" ]; then
	clear
	read -p "Enter workchain id: " workchain_id
	nonce="-1"
	try_generate_different_address="y"
	while [ "$try_generate_different_address" == "y" ]; do
		nonce=$(($nonce+1))
		if ! fift -s ../wallet-new.fif $workchain_id $nonce > /dev/null; then
			exit 1
		fi
		wallet_address=$(cat wallet-address.txt)
		echo "New wallet address $wallet_address"
		read -p "Try generate a different address? [y/n]: " try_generate_different_address
	done
fi

key_file="$1"
if [ "$key_file" == "" ]; then
	clear
	ls -1 | grep ".pk\$"
	read -p "Enter key filename: " key_file
fi

wallet_address=$(cat wallet-address.txt)

lite_client_saveaccount() {
	lite-client -c "last" -c "saveaccount wallet-state.boc $wallet_address" 2>&1
}

lite_client_send_wallet_new() {
	lite-client -c "sendfile wallet-new.boc" 2>&1
}

lite_client_send_wallet_query() {
	lite-client -c "sendfile wallet-query.boc" 2>&1
}


while clear && lite_client_saveaccount | tee /dev/stderr | grep -q "account state is empty"; do
	echo "Send couple of grams to $wallet_address (trying again in 10 seconds)"
	sleep 10
done

while clear && lite_client_saveaccount | tee /dev/stderr | grep -q "account not initialized"; do
	if ! lite_client_send_wallet_new; then
		exit 1
	fi
	echo "Wallet constructor sent (waiting 20 seconds)"
	sleep 20
done


while [ true ]; do
	clear
	if ! fift -s ../wallet-query-commands.fif $key_file; then
		exit 1
	fi

	echo "refresh"
	echo "  refresh wallet state"
	echo ""
	read -p "Enter command: " wallet_command < /dev/tty

	if [ "$wallet_command" == "refresh" ] || [ "$wallet_command" == "" ]; then
			lite_client_saveaccount
	else
		if ! fift -s ../wallet-query.fif $key_file $wallet_command > /dev/null; then
			echo "Invalid command"
			read -p "Try again? [y/n]: " try_again < /dev/tty
			if [ "$try_again" == "n" ]; then
				exit 1
			fi
		else
			lite_client_send_wallet_query
			rm "wallet-query.boc"
			cp "wallet-state.boc" "wallet-state-old.boc"

			while diff "wallet-state.boc" "wallet-state-old.boc" > /dev/null; do
				echo "Downloading new state in 10 seconds"
				sleep 10
				lite_client_saveaccount
			done
		fi
	fi
done
