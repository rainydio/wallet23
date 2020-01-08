# 2/3 wallet

[Original submission]

2/3 multisig wallet contract with signature collection performed on-chain intended to serve single person. Although all three keys have equal permissions, contract is optimized for two keys sending external messages in turns. It is made with the assumption that one of the keys is lost or controlled by attacker.

## State transitions

Unconventionally contract's seqno is not incremented after every external message, instead it represents a single round of collecting signatures. There are three rules within it:

1. Each key is allowed to create only one request for confirmation, afterwards it can only send confirmations.
1. Once confirmation is received requested action is executed, seqno incremented and next request can be sent.
1. If all three keys send different requests, nothing is executed, seqno incremented and next request can be sent.

Because there are three keys, chances of one of them being stolen are higher than if there was only one. However damage is limited only to gas consumed creating single request.

### Request / confirmation

The most optimized transition path involves sending two external messages signed by two different keys. First creating request followed by confirmation from another key. The distinction between request and confirmation is only in which external message is processed first. Both external messages can be sent simultaneously, because seqno is not incremented until the next round.

### Request / cancellation / cancellation confirmation

Instead of sending confirmation another key may send cancellation request. Although neither of two keys can send requests anymore, sending confirmations is still allowed. Confirmed cancellation starts new round without sending any outbound messages.

### Other transitions

Outbound message request is represented by valid message cell, while cancellation request is represented by cell containing no data and optional reference with explanation. It is possible to submit either kind of request at any moment. Only once two keys submit identical cell it is inspected and if its data isn't empty outbound message is sent.

Signature collection may start with cancellation request arriving first. This may happen if it was sent immediately after request it is supposed to cancel, but got included in block earlier.

Instead of sending confirmation or cancellation it is also possible to send alternative outbound message request. Either of two keys will have to confirm other request or third key will have to be used to break the tie.

### Key rotation

Internal message handler handles a single operation to replace one of the keys. Source address of internal message has to be contract itself. So in order to replace key otherwise ordinary request with outbound message to contract itself will have to pass confirmation checks.

## Use cases

All three keys have equal permissions, but they are expected to have distinct roles:

- Main key is the one sending requests made by person owning the wallet.
- Confirmation key is sending confirmations to requests made by main key. The only request that it may should is cancellation request.
- Backup key is stored offline and isn't sending any requests.

Contract serves single person, but there are different use cases depending on who is operating the keys.

### Person performing confirmations

Single person performing confirmations from secondary device is very similar to traditional MFA:

- Main key is stored on desktop PC by wallet software.
- Confirmation key is stored on mobile phone by confirmation software.
- Backup key is stored in sealed paper bag somewhere safe.

Similarly to MFA wide scale attacks such as malware scanning for private keys are ineffective. Backup key can be used to restore access in case one of the devices is lost. Compared to hardware wallet backup key on its own doesn't provide access to funds. Security requirements for storing it are significantly lower. It can be given to a friend or family member.

### Server performing confirmations

If mobile wallet is operating main key then there is no obvious candidate for confirmation device. In that case confirmation key can be generated on server that will automatically confirm requests made by main key. User should be warned about request made by backup key and given enough time to react. Compared to traditional passphrase backup this gives user an early warning.

### Third-party performing confirmations

Server confirmations can be performed by independent confirmation service. Confirmation key can be replaced at any moment and this is the only integration step needed.

Similarly to traditional banks they may choose to contact user by phone to get confirmation for:

- Transfers sent to known phishing addresses.
- Messages sent to vulnerable contracts.
- Suspiciously large transfers.
- Requests made by backup key.
- Requests to replace wallet key.

Honesty and procedures used by confirmation service can be tested. User is vulnerable if he loses either of two other keys. But there is no way for confirmation service to know if user actually lost one or is he performing a test.

## Technicalities

Contract code located in [contract.fif] is small, but relatively sophisticated and is written in ASM.

### Methods

Several methods that query data cell are implemented, some of them accept single `my_key: 256u` argument:

- `seqno`
- `keys` three keys in ascending order.
- `my_request` request cell made by `my_key` or null.
- `other_request1` earliest request cell made by some other key or null.
- `other_request1_key` key that made `other_request1`.
- `other_request2` request cell that was made after `other_request1`.
- `other_request2_key` key that made `other_request2`.

These methods can be called by lite-client runmethod command. Alternatively [lib.fif] contains fift implementations, but with key being bytes instead of integer.

### Examples

Several example scripts are implemented.

- [examples/msg-init.fif] new wallet.
- [examples/msg-simple-transfer.fif] new simple transfer request.
- [examples/msg-cancellation.fif] new cancellation request.
- [examples/msg-confirmation.fif] confirmation.
- [examples/msg-replace-key.fif] new request to replace one of the keys.
- [examples/print-data.fif] prints information stored in data cell.

Many of them also require contract data cell to be downloaded first:

```sh
$ lite-client -c "last" -c "saveaccountdata data.boc <address>"
```

Using them example [examples/wallet.sh] bash script provides simple wallet console application:

![examples/wallet.sh.gif][examples/wallet.sh.gif]

### Init envelope

Contract code does not contain special initialization checks (if seqno is zero). When building stateinit contract code should be wrapped into init envelope. Example [examples/msg-init.fif] script uses such envelope:

```
0 constant nonce

<{
 SETCP0 ACCEPT
 nonce INT
 "../contract.fif" include PUSHREF SETCODE
}>c
```

Additional nonce constant can be tweaked to choose preferred address (e.g. containing only alphanumeric characters). Similarly to subwallet_id used by standard wallet, nonce also allows to operate two wallets with same set of keys. But unlike subwallet_id, nonce isn't included into external message.

### Signing contract address

Hash that is signed is required to include contract address. As a result external message cannot be replayed from or to a different contract (or same contract in different workchain) that is using the same public key and similar payload structure.

### Tests

External message handler is tested by running through all combinations of external messages three keys may send. Report saved into [test-report.txt] contains gas consumed, state description, and outbound message that was sent.

```
TOTAL  GAS   MSG              N  KEY1 KEY2 KEY3  SENT
=====================================================
2566   2566  KEY1_MSG1        1  MSG1
6032   3466  - KEY2_MSG1      2                  MSG1
5256   2690  - KEY2_MSG2      1  MSG1 MSG2
8722   3466    - KEY1_MSG2    2                  MSG2
8826   3570    - KEY2_MSG1    2                  MSG1
...
```

To generate report and compare it to previously committed:

```sh
$ fift -s tests/all.fif > test-report.txt && git difftool test-report.txt
```

[original submission]: https://github.com/rainydio/wallet23/tree/a655b1acb3853b8fa33c34909a43d8e80b977bca
[contract.fif]: https://github.com/rainydio/wallet23/blob/master/contract.fif
[lib.fif]: https://github.com/rainydio/wallet23/blob/master/lib.fif
[examples/msg-init.fif]: https://github.com/rainydio/wallet23/blob/master/examples/msg-init.fif
[examples/msg-simple-transfer.fif]: https://github.com/rainydio/wallet23/blob/master/examples/msg-simple-transfer.fif
[examples/msg-cancellation.fif]: https://github.com/rainydio/wallet23/blob/master/examples/msg-cancellation.fif
[examples/msg-confirmation.fif]: https://github.com/rainydio/wallet23/blob/master/examples/msg-confirmation.fif
[examples/msg-replace-key.fif]: https://github.com/rainydio/wallet23/blob/master/examples/msg-replace-key.fif
[examples/print-data.fif]: https://github.com/rainydio/wallet23/blob/master/examples/print-data.fif
[examples/wallet.sh]: https://github.com/rainydio/wallet23/blob/master/examples/wallet.sh
[examples/wallet.sh.gif]: https://raw.githubusercontent.com/rainydio/wallet23/master/examples/wallet.sh.gif
[test-report.txt]: https://github.com/rainydio/wallet23/blob/master/test-report.txt
