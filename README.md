# 2/3 wallet

Personal 2/3 multisig wallet contract with signature collection performed on-chain. Although all three keys have equal permissions, contract is optimized for two keys sending external messages in turns. It is made with assumption that one of the keys is lost and is controlled by attacker.

### Three parties

It is intended to be operated by three parties providing service to single user.

- Main key stored on device by wallet software.
- Confirmation key stored on server by independent protection service.
- Backup key stored somewhere safe in sealed bag by user.

Advanced users are likely to keep confirmation key to themself. But judging by how often MFA is used by ordinary people most confirmations are likely to be performed server side. Similarly to traditional banks such protection service operating confirmation key may choose to:

- Cancel transactions sent to known phishing addresses.
- Cancel transactions sent to vulnerable contracts.
- Cancel suspiciously large transfers.

It's highly desirable for confirmation key to be operated by independent party. Because signatures are collected on-chain, no additional integration with wallet software is needed.

## State transitions

Unconventionally contract's seqno is not incremented after every external message, instead it represents a single cycle of collecting signatures. There are three rules within it:

1. An individual key can create only a single request waiting for confirmation from another key, afterwards it is locked and can only send confirmation.
1. If two keys agree: confirmed request is executed, seqno incremented, keys are unlocked.
1. If all three keys disagree: seqno incremented, keys are unlocked.

Locking is necessary to prevent draining wallet funds by attacker who acquired access to only one key.

### Request / confirmation

The most used and optimized transition path involves sending two external messages signed by two different keys. First creating request followed by confirmation from another key. The distinction between request and confirmation is only in which external message is processed first. Combined with the fact that seqno is not incremented until new cycle begins allows both external messages to be sent simultaneously.

### Request / cancellation / cancellation confirmation

In order to reject request confirmation key has to submit cancellation request and it also requires confirmation. Although neither of two keys can create requests anymore, sending confirmation is still allowed. To start new cycle main key needs to confirm cancellation request.

### Other transitions

Normal request to send message out is represented by valid message cell, while cancellation request is represented by cell containing no data and optional reference to cell with explanation. It is possible to submit either kind of request at any moment. Only once two keys submit identical cell its data is inspected and if it isn't empty outgoing message is sent.

It is completely possible to start signature collection with cancellation request. This may happen if it was sent immediately after request it is supposed to cancel, but was included in block earlier.

It is possible to submit two different requests to send message out. This may happen under extreme conditions when attacker controls one of the keys. Rightful owner should be able to create alternative request that cannot be blocked.

### Changing the keys

Contract handles a single internal operation to change one key at a time. The source address has to be contract itself. So in order to change key otherwise ordinary request to send message to contract itself needs to pass confirmation checks.

## Technicalities

Contract is small and written in ASM. Each TVM instruction in external message handler was chosen to reduce gas usage.

### Wallet constructor

Unlike _standard_ wallet it doesn't use subwallet_id variable stored in state. Instead there is additional nonce parameter during creation that is used to randomize wallet address. It can be tweaked to choose preferred address (containing only alphanumeric characters) and also allows to use two wallets with same set of keys. It is added to stateinit constructor code which is separate ASM contract that is replaced by actual contract body right after:

```
<{ SETCP0 ACCEPT nonce INT "code.fif" include PUSHREF SETCODE }>c
```

This way contract code doesn't need to include any special checks for first message (if seqno is zero). Also nonce is dropped, it isn't used by contract itself, and is not required to be included into external message.

### Signing contract address

Instead hash that is signed is required to include contract address. This is to ensure that message cannot be replayed from or to a different contract (or same contract in different workchain) that is using same public key and similar payload structure.

### Send raw message mode is set to 3

There is no reason to allow user to set message flags. So the first two flags that are absolutely necessary are used:

- _+1 Sender wants to pay transfer fees separately._ There is no-one else to pay those fees.
- _+2 Any errors arising while processing this message during the action phase should be ignored._ Otherwise state is reverted and faulty external message can be replayed.

Other two flags aren't used:

- _+64 To carry all the remaining value of the inbound message._ There is no value attached to inbound external message.
- _+128 To carry all the remaining balance of the current smart contract._ Although has potential use (quite dangerous) supporting it increases gas consumption by 15%.

### Valid until for external message

External message valid_until parameter restricts time when inbound external message can be accepted by contract. It has no effect on how long it might take to receive confirmation. There is no parameter controlling request expiration.

### External message structure

Message structure is similar to the simpliest wallet but lacks mode parameter.

```
signature B, seqno 32 u, valid_until 32 u, out_msg ref,
```

But hash that is signed additionally includes contract address

```
b{100} s, contract_address addr, seqno 32 u, valid_until 32 u, out_msg ref,
```

Cancellation request is represented by empty cell with optional cell reference that contains explanation using same format as simple transfer body.

## Tests

Contract is optimized for two keys interacting in turns. When third key is involved it attempts to _take place_ of some other key. It is intrinsically dangerous to have such special rules, but the performance gains of assuming which key will be used next are significant. There is an automated test suite which runs through all possible combinations that those keys may send external messages in. The report contains state description, gas used, and also intercepts whatever was sent through send_raw_message:

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

This report only includes messages that were accepted by contract. If you attempt to make changes to contract and your difftool can show inline changes (meld can), then you may create new report and compare it to commited:

```sh
$ (fift -s test.fif key1 && fift -s test.fif key2 && fift -s test.fif key3) > test-report.txt && git difftool test-report.txt
```
