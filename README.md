# 2/3 wallet

Personal wallet contract that requires two signatures to send message out. Signature collection is performed on-chain in multi-step request/confirmation process. Although all three keys have equal permissions, contract is optimized for two keys performing requests and confirmations while third key is reserved for backup. It's made with assumption that one of the keys may be lost and is controlled by attacker.

### State transitions

There are couple of simple rules that govern state transitions:

- An individual key can only make a single order request. Aftewards it is only allowed to send confirmations. This is to prevent attacker who gained access to a single key from draining wallet funds.
- Once two keys agree: message is sent, seqno incremented, and all three keys are unlocked.
- If all three keys disagree: nothing is sent, seqno incremented, and all three keys are unlocked.

Naturally there are two most used transition paths:

#### Request / request confirmation

1.  key1 sends _message_ request
1.  key2 sends _message_ confirmation
1.  _messsage_ is sent, seqno incremented

#### Request / cancelation / cancelation confirmation

1.  key1 sends _message_ request
1.  key2 sends _cancelation_ request
1.  key1 sends _cancelation_ confirmation
1.  nothing is sent, seqno incremented

Cancelation request is represented by empty message.

## Potential uses

I can see three main scenarios from a single person controling all three keys and up to three different parties involved (users, wallet software, protection service).

### Single user controlling three keys

A simplies case is to use one key at main device (desktop PC), a second key at confirmation device (mobile software), and to store a third key in sealed paper bag somewhere else. The fact that backup key on its own doesn't grant full access to wallet severly lowers its storage requirements. It can be given to family member, only to be used in case one of the devices is lost.

### Mobile wallet software

When primary device is mobile wallet then there is no easy option for confirmation device. In this case wallet developer may choose to generate confirmation key server-side. Most of the requests originating from primary key should be confirmed automatically. If backup key is used then user should be contacted, and all confirmations delayed for a week or so allowing user to react. This way wallet software can offer a safer version of a backup.

But when confirmation process is not controlled by user, then there is a potential to offer more useful service. Also I imagine that wallet software developer would like to ditch that confirmation key to a third party, to ensure that his own engineers cannot access user funds.

### Third party protection service

Because signatures are collected on-chain, it's trivial for a third party to step into the process offering advanced protection services:

- Blacklisting address used for phishing
- Blocking suspiciously large transfers
- Blocking messages that interact with vulnerable contracts

The user may be contacted by phone for confirmation. It's similar to what banks usually do. But in this case protection service does not hold user funds hostage. If it's misbehaving a backup key can be used to change it.

## Technicalities

The contract is quite small and is written in ASM. There are couple of example usage scripts `wallet-new.fif` and `wallet-query.fif`. The later has relatively rich interface and requires wallet state to be downloaded from chain. Instructions how to do that are printed by scripts.

Also there is `wallet.sh` script ([example usage video]), create new empty directory to hold wallet files to play with it.

```sh
$ mkdir mywallet
$ cd mywallet
$ ../wallet.sh
```

### Wallet constructor

Unlike _standard_ wallet this contract doesn't use `subwallet_id` variable stored in state. Instead there is an additional `nonce` parameter durring creating that is used to randomize wallet address. It can be used to choose preferred address (containing only alphanumeric characters) or allows to use two wallets with the same set of keys. It is added to stateinit constructor code which is a separate ASM contract that is replaced by actual contract body right after:

```
<{ SETCP0 ACCEPT nonce INT "code.fif" include PUSHREF SETCODE }>c
```

This way contract doesn't need any special checks for first message (if seqno is zero). Also `nonce` is dropped and isn't used by contract itself. And is not required to be included into a message.

### Signing contract address

Instead the hash that is signed is required to include contract address. This is to ensure that message cannot be replayed from or to a different contract (or same contract in different shard) that is using same public key and similar payload structure.

### Send raw message mode is set to 3

There is no reason to allow user to set message flags. So the first two flags, that are absolutely required are used:

- _+1 Sender wants to pay transfer fees separately._
  There is no-one else to pay those fees.
- _+2 Any errors arising while processing this message during the action phase should be ignored._
  Otherwise state will be reverted, and a faulty external message can be replayed.
- _+64 Messages that carry all the remaining value of the inbound message._
  There is no value attached to inbound external message.
- _+128 Messages that are to carry all the remaining balance of the current smart contract._
  Although has potential use (quite dangerous) supporting it costs more gas that it can save.

### Valid until for incoming message

The `valid_until` message parameter restricts time when incoming external message will be accepted by contract. It has no effect on how long it might take to confirm message. There is no parameter controlling pending request expiration.

### External message structure

Resulting message structure is similar to the simpliest wallet but lack mode parameter.

```
signature B, seqno 32 u, valid_until 32 u, intmsg_out ref,
```

And hash that is signed is build from cell that includes contract address

```
b{100} s, contract_address addr, seqno 32 u, valid_until 32 u, intmsg_out ref,
```

A cancellation request is an empty message, or alternatively any invalid message when send_raw_message mode 2 is fixed.

### Key rotation

Contract contains internal message handler that handles a single operation to change keys. The internal message creating request must come from contract itself. To prevent potential lock-out only one key at a time can be changed.

## Tests

Contract is optimized for two keys interacting in turns. When third key is involved it attempts to _take place_ of some other key. It is intrinsically dangerous to have such special rules, but the performance gains of assuming which key will be used next are significant. There is an automated test suite which runs through all possible combinations that those keys may send messages in. The resulting report contains state description, gas used, and also intercepts whatever was sent through send_raw_message:

```
ERR  MSG                SENT   N   KEY1 KEY2 KEY3    GAS   TOTAL
================================================================
OK   KEY1_MSG1                 1   MSG1             2666    2666
OK   - KEY2_MSG1        MSG1   2                    3389    6055
OK   - KEY2_MSG2               1   MSG1 MSG2        2790    5456
OK     - KEY1_MSG2      MSG2   2                    3389    8845
OK     - KEY2_MSG1      MSG1   2                    3493    8949
...
```

This report only includes successful executions and unexpected errors, otherwise there will be to many rows in it. If you attempt to make changes to contract, and your difftool can show inline changes (meld can). Then you may create new report and compare it to previously commited:

```sh
$ (fift -s test.fif key1 && fift -s test.fif key2 && fift -s test.fif key3) > test-report.txt && git difftool test-report.txt
```

This way it's super easy to spot any errors and to track gas usage.

[example usage video]: https://youtu.be/1Si--TuRiTE
