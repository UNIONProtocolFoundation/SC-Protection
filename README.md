# Union Smart Contract Protection contracts

In this acticle


- [List of contract with descriptions](#list-of-contract-with-descriptions)
- [UnionSCPool](#unionscpool)
- [SCProtections](#scprotections)
- [SCPClaims](#scpclaims)

## List of contract with descriptions:

### UnionSCPool

Dedicated to assemble capital (in form of ERC20 tokens) and use it for backing protections. The system makes money from selling protections and it’s revenue comes from distributing matured protections premiums.

UnionSCPool inherits UnionERC20Pool and introduces SC-P specific features like:
1.	`ppID` - a smart contract protocol identiier (1 pool instance to back 1 protocol protections)
2.  pool locking for deposit/withdraw when a Claim for protections payout is filled for the referenced protocol
3.  Protections payouts feature based on a Claim status.    

### SCProtections

Storage or all Smart Contract (SC) protections issued by UnionProtocol. Is referenced by uUNNToken. This contracts provides the following features for users:

1.	Selling of the SC Protections (create & createTo functions) - creates and sells SCProtection.
2.	Exercises SCProtections - when Claim is Approved. 
3.	Provides an interface for keeping accompanied documentation for SCProtections. 
4.	Implements Pausable feature
5.	Implements ACL.

### SCPClaims

Storage and operational contract for Smart Contract protection Claims. Claim can be filled by anyone who thinks that a protocol is hacked (for example) by invoking `fillClaim` function and paying a claiming fee. This trigers a start of a Claim lifecycle workflow that may lead in Approved or Rejected state. If Approved, then all relevant protections backed by the protocol-dedicated UnionSCPool can be exercised. Rejected state gives no opportunity to exercise protection, but this state could be challenged and then result in either Approved or AppealRejected state. Approved state allows for exercising protections, AppealRejected is a terminal state and doesn't allow for any further actions. 
