// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// lend structure
struct lendInfo {
  uint256 lendId;
  uint256 depositTime;
  uint256 amount;
}

// borrow structure
struct borrowInfo {
  uint256 startDate;
  uint256 endDate;
  uint256 borrowId;
  string state;
  uint256 dueDate;
  uint256 APR;
  uint256 borrowAmount;
  uint256 paybackAmount;
}


library InterestLib {
  function calculateInterestMatured(
    mapping(address => lendInfo[]) storage Lender,
    address user,
    uint256 lendAPR
  ) internal view returns (uint256) {
    uint256 totalInterest;
    // for every lend position calculate the interest
    for (uint256 i = 0; i < Lender[user].length; i++) {
      if (Lender[user][i].amount == 0) continue;
      totalInterest +=
        ((block.timestamp - Lender[user][i].depositTime) * lendAPR * Lender[user][i].amount) /
        (100 * 365 days);
    }
    return totalInterest;
  }

  function calculatePenalty(
    mapping(address => borrowInfo[]) storage Borrower,
    uint256 borrowNumber,
    uint256 penalty
  ) internal view returns (uint256) {
    uint256 daysLate = (block.timestamp - Borrower[msg.sender][borrowNumber].dueDate) / 1 days;
    uint256 penaltyAmount = (Borrower[msg.sender][borrowNumber].borrowAmount * penalty * daysLate) /
      (100 * 365);
    return penaltyAmount;
  }
}

contract LoanManager {
  using InterestLib for mapping(address => borrowInfo[]);
  using InterestLib for mapping(address => lendInfo[]);

  address public owner;
  address[] private userAddressList;
  address[] private userBorrowersList;
  address[] private userLendersList;
  uint256 public borrowersCounter;
  uint256 public lendersCounter;
  uint256 public lendAPR = 3; 
  uint256 public penalty = 25; // percentange applied for late borrowers
  bool private locked;

  function getContractBalance() public view returns (uint256) {
    return address(this).balance;
  }

  mapping(address => borrowInfo[]) public Borrower;
  mapping(address => int256) public borrowCount; //total numbers of borrow position for every user

  mapping(address => lendInfo[]) public Lender;
  mapping(address => uint256) public interestMatured;

  mapping(address => uint256) public netPosition;

  constructor() {
    owner = msg.sender;
  }

  function getUserBorrowerList() public view returns (address[] memory) {
    return userBorrowersList;
  }

  function getUserLendersList() public view returns (address[] memory) {
    return userLendersList;
  }

  //Register a user its category based on the action completed
  function checkCategoryRegistration(address[] storage list, address[] storage list2) internal {
    bool found;
    bool found2;
    //check if user is on the first list (borrower/lender)
    for (uint256 i = 0; i < list.length; i++) {
      if (list[i] == msg.sender) {
        found = true;
        break;
      }
    }
    //if not in first list add it
    if (!found) {
      list.push(msg.sender);
    }
    // if not in first category check second
    for (uint256 i = 0; i < list2.length; i++) {
      if (list2[i] == msg.sender) {
        found2 = true;
        break;
      }
    }
    // if address is not in any list add it in the userAddressList
    if (found == false && found2 == false) {
      userAddressList.push(msg.sender);
    }
  }


  modifier checkWeeksRange(uint256 _weeks) {
    require(_weeks <= 260, 'Invalid week number');
    _;
  }

 
  modifier checkMinimalBorrow(uint256 amount) {
    require(amount >= 0.2 ether, 'Minimal borrow is 0.2 Eth');
    _;
  }

  modifier checkMinimalLend() {
    require(msg.value >= 0.1 ether, 'Minimal lend is 0.1 Eth');
    _;
  }

  modifier checkNetPosition(uint256 amount) {
    require(netPosition[msg.sender] >= amount, 'Excedeed maximum withdraw');
    _;
  }

  modifier nonReentrant() {
    require(!locked, 'Reentrancy');
    locked = true;
    _;
    locked = false;
  }

  modifier checkContractBalance(uint256 amount) {
    require(this.getContractBalance() >= amount);
    _;
  }

  event lendDone(address who, uint256 howMuch, uint256 when);

  event borrowRepaid(address who, uint256 howmuch, uint256 when, uint256 initialBorrow);

  event withdrawDone(address who, uint256 howMuch, uint256 when);

  function lend() public payable checkMinimalLend {
    netPosition[msg.sender] += msg.value;
    checkCategoryRegistration(userLendersList, userBorrowersList);
    lendersCounter = userLendersList.length;
    // register lend information
    Lender[msg.sender].push(
      lendInfo({
        lendId: uint256(Lender[msg.sender].length) + 1,
        depositTime: block.timestamp,
        amount: msg.value
      })
    );
    emit lendDone(msg.sender, msg.value, block.timestamp);
  }

  
  function updateInterestMatured() public returns (uint256) {
    uint256 totalInterest = Lender.calculateInterestMatured(msg.sender, lendAPR);
    interestMatured[msg.sender] = totalInterest;
    return interestMatured[msg.sender];
  }

  function withdraw(uint256 amount) public checkNetPosition(amount) nonReentrant {
    require(amount > 0, 'Amount must be greater than zero');
    require(netPosition[msg.sender] >= amount, 'Not enough funds in deposits to cover withdrawal');
    uint256 startingAmount = amount;
    //withdrawing from the first to the last lend position
    for (uint256 i = 0; i < Lender[msg.sender].length; i++) {
      if (amount > Lender[msg.sender][i].amount) {
        amount -= Lender[msg.sender][i].amount;
        Lender[msg.sender][i].amount = 0;
      } else if (Lender[msg.sender][i].amount >= amount) {
        Lender[msg.sender][i].amount -= amount;
        break;
      }
    }
    netPosition[msg.sender] -= startingAmount;
    (bool result, ) = payable(msg.sender).call{ value: startingAmount }('');
    require(result, 'Transaction failed');
    emit withdrawDone(msg.sender, startingAmount, block.timestamp);
  }

  function withdrawInterest() public nonReentrant {
    uint256 interest = updateInterestMatured();
    require(interest > 0, 'No interest to withdraw');
    for (uint256 i = 0; Lender[msg.sender].length > i; i++) {
      Lender[msg.sender][i].depositTime = block.timestamp;
    }
    (bool success, ) = msg.sender.call{ value: interest }('');
    require(success, 'Transaction failed');
    
  }

  function openBorrow(
    uint256 _weeks,
    uint256 amount
)
    public
    payable
    checkWeeksRange(_weeks)
    checkMinimalBorrow(amount)
    checkContractBalance(amount)
    nonReentrant
{
    borrowCount[msg.sender]++; // Increment the user's borrow counter
    

    // Calculate loan due date in seconds (604800 = 1 week)
    uint256 _dueDate = block.timestamp + (_weeks * 604800);

    // Determine APR based on loan duration
    uint256 APR;
    if (_weeks < 24) {
        APR = 7;
    } else if (_weeks >= 24 && _weeks < 104) {
        APR = 6;
    } else APR = 5;

    // Calculate total payback amount (principal + interest)
    uint256 _paybackAmount = amount + ((amount * APR * _weeks) / (100 * 52));
    netPosition[msg.sender] -= _paybackAmount; // Reduce lender's net position by the borrowed amount

    // Store loan details in the borrower's record
    Borrower[msg.sender].push(
      borrowInfo({
        startDate: block.timestamp,
        endDate: 0, // 0 means not yet repaid
        borrowId: uint256(Borrower[msg.sender].length) + 1,
        state: 'Active',
        dueDate: _dueDate,
        APR: APR,
        borrowAmount: amount,
        paybackAmount: _paybackAmount
      })
    );

    // register borrower in user lists and update counters
    checkCategoryRegistration(userBorrowersList, userLendersList);
    borrowersCounter = userBorrowersList.length;

    // Transfer borrowed funds to borrower
    (bool success, ) = msg.sender.call{ value: amount }('');
    require(success, 'Transaction failed');
}

function calculatePenalty(uint256 borrowNumber) internal view returns (uint256) {
    // delegate penalty calculation to InterestLib
    uint256 penaltyAmount = Borrower.calculatePenalty(borrowNumber, penalty);
    return penaltyAmount;
}

function payBorrow(uint256 borrowNumber) public payable nonReentrant {
    // Ensure the loan is active before repayment
    require(
      keccak256(bytes(Borrower[msg.sender][borrowNumber].state)) == keccak256(bytes('Active')),
      'Borrow selected not active'
    );
    require(msg.value > 0, 'Repayment must be more than 0');
    require(borrowNumber < Borrower[msg.sender].length, 'Invalid borrow index');

    // if overdue, add penalty to payback amount
    if (block.timestamp > Borrower[msg.sender][borrowNumber].dueDate) {
      Borrower[msg.sender][borrowNumber].paybackAmount += calculatePenalty(borrowNumber);
    }

    // Case 1: Overpayment — refund surplus
    if (msg.value > Borrower[msg.sender][borrowNumber].paybackAmount) {
      uint256 difference = msg.value - Borrower[msg.sender][borrowNumber].paybackAmount;
      netPosition[msg.sender] += msg.value - difference; // Credit only the required amount
      Borrower[msg.sender][borrowNumber].state = 'Paid';
      (bool success, ) = msg.sender.call{ value: difference }('');
      require(success, 'Transaction failed');

    // Case 2: Exact payment
    } else if (msg.value == Borrower[msg.sender][borrowNumber].paybackAmount) {
      netPosition[msg.sender] += msg.value;
      Borrower[msg.sender][borrowNumber].state = 'Paid';

    // case 3: Underpayment — revert transaction
    } else {
      revert('Payment is lower than the amount requested');
    }

    // Record repayment date
    Borrower[msg.sender][borrowNumber].endDate = block.timestamp;

    // Emit repayment event
    emit borrowRepaid(
      msg.sender,
      Borrower[msg.sender][borrowNumber].paybackAmount,
      block.timestamp,
      Borrower[msg.sender][borrowNumber].borrowAmount
    );
}
}