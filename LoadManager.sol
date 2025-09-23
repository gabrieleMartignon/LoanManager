// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

struct lendInfo {
  uint256 lendId;
  uint256 depositTime;
  uint256 amount;
}

struct borrowInfo {
  uint256 startDate;
  uint256 endDate;
  uint256 borrowId;
  string state;
  uint256 dueDate;
  uint256 APY;
  uint256 borrowAmount;
  uint256 paybackAmount;
}

library InterestLib {
  function calculateInterestMatured(
    mapping(address => lendInfo[]) storage Lender,
    address user,
    uint256 lendAPY
  ) internal view returns (uint256) {
    uint256 totalInterest;
    for (uint256 i = 0; i < Lender[user].length; i++) {
      if (Lender[user][i].amount == 0) continue;
      totalInterest +=
        ((block.timestamp - Lender[user][i].depositTime) * lendAPY * Lender[user][i].amount) /
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
  uint256 public lendAPY = 3;
  uint256 public penalty = 25;
  bool private locked;

  function getContractBalance() public view returns (uint256) {
    return address(this).balance;
  }

  mapping(address => borrowInfo[]) public Borrower;
  mapping(address => int256) public borrowCount;

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

  //Aggiunta di un untente alla propria categoria (lender/borrower) e al counter di utenti univoci.
  function checkCategoryRegistration(address[] storage list, address[] storage list2) internal {
    bool found;
    bool found2;
    //controllo che l' utente che invoca la funzione non sia già presenta nella prima categoria
    for (uint256 i = 0; i < list.length; i++) {
      if (list[i] == msg.sender) {
        found = true;
        break;
      }
    }
    //se non è presente aggiungilo
    if (!found) {
      list.push(msg.sender);
    }
    // controllo se è presente nella seconda categoria
    for (uint256 i = 0; i < list2.length; i++) {
      if (list2[i] == msg.sender) {
        found2 = true;
        break;
      }
    }
    // se non è presente in nessuna delle due liste lo aggungo anche nella lista degli utenti complessivi
    if (found == false && found2 == false) {
      userAddressList.push(msg.sender);
    }
  }

  //controllo l' intervallo delle settimane
  modifier checkWeeksRange(uint256 _weeks) {
    require(_weeks <= 260, 'Invalid week number');
    _;
  }

  //controllo l' intervallo della somma da prednere in prestito/ritirare
  modifier checkMinimalBorrow(uint256 amount) {
    require(amount > 0.2 ether, 'Minimal borrow is 0.2 Eth');
    _;
  }

  modifier checkMinimalLend() {
    require(msg.value > 0.1 ether, 'Minimal lend is 0.1 Eth');
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
    uint256 totalInterest = Lender.calculateInterestMatured(msg.sender, lendAPY);
    interestMatured[msg.sender] = totalInterest;
    return interestMatured[msg.sender];
  }

  function withdraw(uint256 amount) public checkNetPosition(amount) nonReentrant {
    require(amount > 0, 'Amount must be greater than zero');
    require(netPosition[msg.sender] >= amount, 'Not enough funds in deposits to cover withdrawal');
    uint256 startingAmount = amount;
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
    (bool success, ) = msg.sender.call{ value: interest }('');
    require(success, 'Transaction failed');
    for (uint256 i = 0; Lender[msg.sender].length > i; i++) {
      Lender[msg.sender][i].depositTime = block.timestamp;
    }
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
    borrowCount[msg.sender]++;
    netPosition[msg.sender] -= amount;
    uint256 _dueDate = block.timestamp + (_weeks * 604800);
    uint256 APY;
    if (_weeks < 24) {
      APY = 7;
    } else if (_weeks >= 24 && _weeks < 104) {
      APY = 6;
    } else if (_weeks >= 104 && _weeks <= 260) {
      APY = 5;
    } else APY = 4;
    uint256 _paybackAmount = amount + ((amount * APY * _weeks) / (100 * 52));
    Borrower[msg.sender].push(
      borrowInfo({
        startDate: block.timestamp,
        endDate: 0,
        borrowId: uint256(Borrower[msg.sender].length) + 1,
        state: 'Active',
        dueDate: _dueDate,
        APY: APY,
        borrowAmount: amount,
        paybackAmount: _paybackAmount
      })
    );
    checkCategoryRegistration(userBorrowersList, userLendersList);
    borrowersCounter = userBorrowersList.length;
    (bool success, ) = msg.sender.call{ value: amount }('');
    require(success, 'Transaction failed');
  }

  function calculatePenalty(uint256 borrowNumber) internal view returns (uint256) {
    uint256 penaltyAmount = Borrower.calculatePenalty(borrowNumber, penalty);
    return penaltyAmount;
  }

  function payBorrow(uint256 borrowNumber) public payable nonReentrant {
    require(
      keccak256(bytes(Borrower[msg.sender][borrowNumber].state)) == keccak256(bytes('Active')),
      'Borrow selected not active'
    );
    require(msg.value > 0, 'Repayment must be more than 0');
    require(borrowNumber < Borrower[msg.sender].length, 'Invalid borrow index');

    if (block.timestamp > Borrower[msg.sender][borrowNumber].dueDate) {
      Borrower[msg.sender][borrowNumber].paybackAmount += calculatePenalty(borrowNumber);
    }

    if (msg.value > Borrower[msg.sender][borrowNumber].paybackAmount) {
      uint256 difference = msg.value - Borrower[msg.sender][borrowNumber].paybackAmount;
      netPosition[msg.sender] += msg.value - difference;
      Borrower[msg.sender][borrowNumber].state = 'Paid';
      (bool success, ) = msg.sender.call{ value: difference }('');
      require(success, 'Transaction failed');
    } else if (msg.value == Borrower[msg.sender][borrowNumber].paybackAmount) {
      netPosition[msg.sender] += msg.value;
      Borrower[msg.sender][borrowNumber].state = 'Paid';
    } else {
      revert('Payment is lower than the amount requested');
    }
    Borrower[msg.sender][borrowNumber].endDate = block.timestamp;
    emit borrowRepaid(
      msg.sender,
      Borrower[msg.sender][borrowNumber].paybackAmount,
      block.timestamp,
      Borrower[msg.sender][borrowNumber].borrowAmount
    );
  }
}
