# 2/3 wallet

[Original Telegram contest submission]

2/3 multisig wallet contract with signature collection performed on-chain intended to serve single person. Although all three keys have equal permissions, contract is optimized for two keys sending external messages in turns. It is made with assumption that one of the keys is lost and is controlled by attacker.

## State transitions

Unconventionally contract's seqno is not incremented after every external message, instead it represents a single round of collecting signatures. There are three rules within it:

1. Each key is allowed to create only one request for confirmation, aftewards it can only send confirmations.
1. Once confirmation is received requested action is executed, seqno incremented and next request can be sent.
1. If all three keys send different requests, nothing is executed, seqno incremented and next request can be sent.

Because there are three keys, chances of one of them being stolen are higher then if there was only one. However damage is limited only to gas consumed creating single request.

### Request / confirmation

The most used and optimized transition path involves sending two external messages signed by two different keys. First creating request to send outbound message followed by confirmation from another key. The distinction between request and confirmation is only in which external message is processed first. Combined with the fact that seqno is not incremented until next round allows both external messages to be sent simultaneously.

### Request / cancellation / cancellation confirmation

Instead of sending confirmation another key may send cancellation request. Although neither of two keys can send requests anymore, sending confirmations is still allowed. Confirmed cancellation starts new round without sending any outbound messages.

### Other transitions

Outbound message request is represented by valid message cell, while cancellation request is represented by cell containing no data and optional reference with explanation. It is possible to submit either kind of request at any moment. Only once two keys submit identical cell it is inspected and if its data isn't empty outbound message is sent.

It is completely possible to start signature collection with cancellation request arriving first. This may happen if it was sent immediately after request it is supposed to cancel, but got included in block earlier.

Although usually only one of the keys will be requesting oubound messages, instead of sending confirmation or cancellation another key can also send different outbound message request. All three keys have equal permissions and single key can't prevent other two from sending different outbound message.

### Key rotation

Contract's internal message handler handles a single operation to replace one of the keys. Source address of internal message has to be contract itself. So in order to replace key otherwise ordinary request with outbound message to contract itself needs to pass confirmation checks.

## Use cases

All three keys have equal permissions, but they are expected to have distinct roles:

- Main key is the one sending requests made by person owning the wallet.
- Confirmation key is sending confirmations to requests made by main key. The only request that it may send is cancellation request.
- Backup key is stored offline and isn't sending any requests.

Contract serves single person, but there are different use cases depending on who is operating cryptographic keys.

### Person performing confirmations

Single person performing confirmations from secondary device is very similar to traditional MFA:

- Main key is stored on desktop PC by wallet software.
- Confirmation key is stored on mobile phone by confirmation software.
- Backup key is stored in sealed paper bag somewhere safe.

Similiraly to MFA wide scale attacks such as malware scanning for private keys are ineffective. Backup key can be used to restore access in case one of devices is lost. Compared to hardware wallet backup key on its own doesn't provide access to funds. Security requirements for storing it are significantly lower. It can be given to friend or family member.

### Server performing confirmations

If mobile wallet is operating main key then there is no obvious candidate for confirmation device. In that case confirmation key can be generated on server that will automatically confirm requests made by main key. User should be warned about request made by backup key. He should be given enough time to react in case he had not authorized it. Compared to traditional passphrase backup this gives user an early warning.

### Third-party performing confirmations

It's highly desirable for server confirmations to be performed by independent confirmation service. Confirmation key can be replaced at any moment and this is the only integration step needed.

Similarly to traditional banks they may choose to contact user by phone to get confirmation for:

- Transfers sent to known phishing addresses.
- Messages sent to vulnerable contracts.
- Suspiciously large transfers.
- Requests made by backup key.
- Requests to replace wallet key.

Honesty and procedures used by confirmation service can be tested. User is vulnarable if he looses either of two other keys. But there is no way to know if user actually lost one of his keys or is he performing a test.

## Technicalities

Contract is written in ASM. Automated test in [test-report.fif] runs through all combinations of external messages three keys may send. Report is saved into [test-report.txt] and contains state description, outbound message that was sent, and gas consumed.

```
ERR  MSG                SENT   N   KEY1 KEY2 KEY3    GAS   TOTAL   LAST PREV THRD
=================================================================================
OK   KEY1_MSG1                 1   MSG1             2566    2566   KEY1 KEY2 KEY3
OK   - KEY2_MSG1        MSG1   2                    3466    6032   KEY2 KEY1 KEY3
OK   - KEY2_MSG2               1   MSG1 MSG2        2690    5256   KEY2 KEY1 KEY3
OK     - KEY1_MSG2      MSG2   2                    3466    8722   KEY1 KEY2 KEY3
OK     - KEY2_MSG1      MSG1   2                    3570    8826   KEY2 KEY1 KEY3
...
```

To generate report and compare it to previously committed:

```sh
$ (fift -s test-report.fif key1 && fift -s test-report.fif key2 && fift -s test-report.fif key3) > test-report.txt && git difftool test-report.txt
```

### Init envelope

Contract code does not contain special initialization checks (if seqno is zero). When building stateinit contract code should be wrapped into init envelope. Example [wallet-new.fif] script uses such envelope:

```
0 constant nonce

<{
  SETCP0 ACCEPT
  nonce INT
  "code.fif" include PUSHREF SETCODE
}>c
```

Additional nonce constant can be tweaked to choose preferred address (e.g. containing only alphanumeric characters). Similarly to subwallet_id used by standard wallet, nonce also allows to operate two wallets with same set of keys. But unlike subwallet_id, nonce isn't included into external message.

### Signing contract address

Instead hash that is signed is required to include contract address. So external message cannot be replayed from or to a different contract (or same contract in different workchain) that is using same public key and similar payload structure.

### Valid until

External message includes valid_until field that restricts time when it can be accepted by contract. It has no effect on how long it might take to receive confirmation. There is no parameter controlling request expiration.

### Mode

There is no reason to allow custom outbound message mode, first two necessary flags are used:

- _+1 Sender wants to pay transfer fees separately._ There is no-one else to pay them.
- _+2 Any errors arising while processing this message during the action phase should be ignored._ Otherwise state is reverted and faulty external message can be replayed.
- _+64 To carry all the remaining value of the inbound message._ There is no value attached to inbound external message.
- _+128 To carry all the remaining balance of the current smart contract._ Although has potential use (quite dangerous) supporting it increases gas consumption by 15%.

### Contract data

Requests are stored as nullable reference by using additional bit that is 0 when null is stored or 1 when reference is stored. Non-standard fift serialization primitive `nullref,` is used to denote it (instead of otherwise equivalent `dict,`).

```
seqno 32 u,
last_request nullref,
last_key 256 u,
third_key 256 u,
prev_key 256 u,
prev_request nullref,
```

Notably contract data cell adapts to usage pattern. Key at the end is most likely to send external message and its signature is checked first. If that failed then inexpensive operation reversing 5 items switches perspective to second most likely key.

Using third key invokes relatively complex and expensive procedure of swapping it with one of two other keys. Such special treatment introduces additional risks.

### External message format

Because outbound message request is represented by valid message cell, external message body layout is similar to one used by simpliest wallet, but lacks mode field:

```
signature B,
seqno 32 u,
valid_until 32 u,
out_msg ref,
```

Importantly hash that is signed is built from cell that includes contract address:

```
b{100} s,
contract_address addr,
seqno 32 u,
valid_until 32 u,
out_msg ref,
```

[original telegram contest submission]: https://github.com/rainydio/wallet23/tree/a655b1acb3853b8fa33c34909a43d8e80b977bca
