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

The most used and optimized transition path involves sending two external messages signed by two different keys. First creating outbound message request followed by confirmation from another key. The distinction between request and confirmation is only in which external message is processed first. Combined with the fact that seqno is not incremented until new cycle begins allows both external messages to be sent simultaneously.

### Request / cancellation / cancellation confirmation

In order to reject request confirmation key has to submit cancellation request that also requires confirmation. Although neither of two keys can create requests anymore, sending confirmation is still allowed. To start new cycle main key needs to confirm cancellation request.

### Other transitions

Outbound message request is represented by valid message cell, while cancellation request is represented by cell containing no data and optional reference with explanation. It is possible to submit either kind of request at any moment. Only once two keys submit identical cell its data is inspected and if it isn't empty outbound message is sent.

It is completely possible to start signature collection with cancellation request arriving first. This may happen if it was sent immediately after request it is supposed to cancel, but got included in block earlier.

It is possible to submit two different outbound message requests. Generally confirmation key should not submit outbound message request that was not previously signed by main key. But contract doesn't treat keys differently and alternative outbound message request is required when attacker controls one of the keys.

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

### Valid until

External message contains valid_until field that restricts time when it can be accepted by contract. It has no effect on how long it might take to receive confirmation. There is no parameter controlling request expiration.

### Mode

There is no reason to allow user to set mode. So the first two flags that are absolutely necessary are used:

- _+1 Sender wants to pay transfer fees separately._ There is no-one else to pay them.
- _+2 Any errors arising while processing this message during the action phase should be ignored._ Otherwise state is reverted and faulty external message can be replayed.

Other two flags aren't used:

- _+64 To carry all the remaining value of the inbound message._ There is no value attached to inbound external message.
- _+128 To carry all the remaining balance of the current smart contract._ Although has potential use (quite dangerous) supporting it increases gas consumption by 15%.

## Contract data

Request that is waiting for confirmation is stored as reference in contract data cell. But if there isn't one then null is stored instead. For performance reasons contract uses dictionary instructions to store such nullable reference. Dictionary store and load instructions use additional bit within cell data. That bit is 0 when null is stored, and it is 1 when cell reference is stored instead. Text below describes formats using fift serialization primitives and not to be confused with dictionaries non-standard serialization primitive `nullref,` is used instead (equivalent to `dict,`).

```
seqno 32 u,
last_request nullref,
last_key 256 u,
third_key 256 u,
prev_key 256 u,
prev_request nullref,
```

Notably two keys along with requests are not stored at fixed positions, instead position within data cell depends on usage pattern. It is stored that way to increase performance. The key that is most likely to send external message is at the end. And reversing last 5 items switches perspective to the next most likely key.

Using third key invokes relatively complex and expensive procedure of swapping it with one of two other keys. It is intrinsically dangerous to have such special rule, but the performance gains of assuming which key will be used next are significant. There is automated test suite that runs through all possible combinations of external messages three keys may send. The report contains state description, gas used, and outbound message that was sent.

```
ERR  MSG                SENT   N   KEY1 KEY2 KEY3    GAS   TOTAL
================================================================
OK   KEY1_MSG1                 1   MSG1             2566    2566
OK   - KEY2_MSG1        MSG1   2                    3466    6032
OK   - KEY2_MSG2               1   MSG1 MSG2        2690    5256
OK     - KEY1_MSG2      MSG2   2                    3466    8722
OK     - KEY2_MSG1      MSG1   2                    3570    8826
...
```

To generate report and compare it to previously committed:

```sh
$ (fift -s test.fif key1 && fift -s test.fif key2 && fift -s test.fif key3) > test-report.txt && git difftool test-report.txt
```

## External message format

Given that `out_msg` is valid outbound message cell, external message body is similar to one used by simpliest wallet, but lacks mode field:

```
signature B, seqno 32 u, valid_until 32 u, out_msg ref,
```

Importantly hash that is signed includes contract address:

```
b{100} s, contract_address addr, seqno 32 u, valid_until 32 u, out_msg ref,
```

Everything together creating external message cell:

```
<b b{1000} s, b{100} s, contract_address addr, 0 Gram, b{00} s,

  <b b{100} s, contract_address addr,
    seqno 32 u, valid_until 32 u, out_msg ref,
  b> hashu privkey ed25519_sign_uint B,

  seqno 32 u, valid_until 32 u, out_msg ref,
b>
```

Cancellation is represented by cell containing no data, so external message carrying simpliest cancellation:

```
<b b{1000} s, b{100} s, contract_address addr, 0 Gram, b{00} s,

  <b b{100} s, contract_address addr,
    seqno 32 u, valid_until 32 u, <b b> ref,
  b> hashu privkey ed25519_sign_uint B,

  seqno 32 u, valid_until 32 u, <b b> ref,
b>
```

Additionally cancellation cell may include optional reference with explanation encoded using simple transfer format.
