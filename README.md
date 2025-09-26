# LoanManager 


## Project overview 

LoanManager is a Solidity Smart Contract that implements a peer-to-peer on-chain pool-based lending platform.  
Lenders deposit ETH and earn interest over time, while borrowers draw funds from the contract. Borrowers pay interest based on the selected loan duration, and they incur penalties if they are late with repayment. The repayment period is chosen by the user when opening the position.  
You can find the contract deployed on Sepolia at this address **0xEb19D9453Be1440b9dc8a26AcbA675321BdaED6a**.

---

## Features
- User tracking: lists for lenders, borrowers, and all users.  
- Lend: lend ETH to gain interest.  
- Borrow: open loans with duration in weeks, APY determined by duration.  
- Repay: single‑payment repayment flow with exact/overpayment handling and underpayment rejection.  
- Interest withdrawal: interest accrued on deposited funds is tracked in a separate variable and can be withdrawn independently.  
- Penalties: applied when a borrower repays after the due date. The penalty is calculated only for the period exceeding the agreed repayment time.  
- Basic protections: minimal amount checks, contract liquidity check, anti‑reentrancy boolean lock.  
- Events: emits events for main actions such as lend, withdraw, and repay.  

---

## Code structure
- Structs  
  - `lendInfo`: contains info about a single deposit.  
  - `borrowInfo`: contains info about a borrow position.  
- Library Functions  
  - `calculateInterestMatured()`: sums simple interest per lend position.  
  - `calculatePenalty()`: computes penalty based on days late and principal.  
- Contract  
  - `LoanManager`: state variables, mappings, modifiers, events, and functions.  

---

## How to use
- Clone this repository.  
- Import the project into an IDE that can compile Solidity ^0.8.0 and above (like [Remix](https://remix.ethereum.org/#lang=en)).  
- Compile.  
- Go to the **Deploy & Run Transactions** tab and select an environment (Injected Web3 for Testnet). Make sure you have the MetaMask extension installed and click on **Deploy**.  
- Now that the contract is on-chain you can interact with it!  

---

## License
MIT

---

## Risks & disclaimers
This project is a learning prototype. Do not deploy to mainnet with real funds without audits, thorough testing, and legal review. Economic parameters (minimums, APY, penalty) are illustrative and must be tuned for production.
LoanManager is a pool‑based lending prototype. This means that all lenders’ deposits are aggregated into a common liquidity pool from which borrowers can draw funds.  
Because the contract does not enforce collateralization, a borrower could in theory take out a loan and choose not to repay it. In such a case, lenders would bear the loss.  
This behavior is intentional in the prototype to demonstrate the mechanics of pooled lending, but it also highlights the importance of adding collateral or other risk‑mitigation mechanisms before any production deployment.


---

## Contacts
**Gabriele Martignon** | Master in Blockchain Development | Blockchain & Web3 Developer  
- Personal Portfolio: https://gabrielemartignon.github.io/  
- Email: gabrielemartignon@gmail.com  
- GitHub Profile: https://github.com/gabrieleMartignon  
- LinkedIn: https://www.linkedin.com/in/gabrielemartignon  
- Contract: https://sepolia.etherscan.io/address/0xEb19D9453Be1440b9dc8a26AcbA675321BdaED6a

