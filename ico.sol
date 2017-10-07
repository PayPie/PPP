pragma solidity ^ 0.4.17;

contract SafeMath {
    function safeMul(uint a, uint b) pure internal returns(uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function safeSub(uint a, uint b) pure internal returns(uint) {
        assert(b <= a);
        return a - b;
    }

    function safeAdd(uint a, uint b) pure internal returns(uint) {
        uint c = a + b;
        assert(c >= a && c >= b);
        return c;
    }
}

contract ERC20 {
    uint public totalSupply;

    function balanceOf(address who) public view returns(uint);

    function allowance(address owner, address spender) public view returns(uint);

    function transfer(address to, uint value) public returns(bool ok);

    function transferFrom(address from, address to, uint value) public returns(bool ok);

    function approve(address spender, uint value) public returns(bool ok);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}


contract Ownable {
    address public owner;

    function Ownable() public {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) 
            owner = newOwner;
    }

    function kill() public {
        if (msg.sender == owner) 
            selfdestruct(owner);
    }

    modifier onlyOwner() {
        if (msg.sender == owner)
            _;
    }
}

contract Pausable is Ownable {
    bool public stopped;

    modifier stopInEmergency {
        if (stopped) {
            revert();
        }
        _;
    }

    modifier onlyInEmergency {
        if (!stopped) {
            revert();
        }
        _;
    }

    // Called by the owner in emergency, triggers stopped state
    function emergencyStop() external onlyOwner() {
        stopped = true;
    }

    // Called by the owner to end of emergency, returns to normal state
    function release() external onlyOwner() onlyInEmergency {
        stopped = false;
    }
}



// Crowdsale Smart Contract
// This smart contract collects ETH and in return sends tokens to the Backers
contract Crowdsale is SafeMath, Pausable {

    struct Backer {
        uint weiReceived; // amount of ETH contributed
        uint tokensSent; // amount of tokens  sent  
        bool refunded; // true if user has been refunded       
    }

    Token public token; // Token contract reference   
    address public multisig; // Multisig contract that will receive the ETH    
    address public team; // Address to which the team tokens will be sent   
    uint public tokensForTeam; // Tokens to be allocated to the team if campaign succeeds
    uint public ethReceived; // Number of ETH received
    uint public totalTokensSent; // Number of tokens sent to ETH contributors
    uint public startBlock; // Crowdsale start block
    uint public endBlock; // Crowdsale end block
    uint public maxCap; // Maximum number of tokens to sell
    uint public minCap; // Minimum number of tokens to sell    
    bool public crowdsaleClosed; // Is crowdsale still in progress
    uint public refundCount;  // number of refunds
    uint public totalRefunded; // total amount of refunds in wei
    uint public tokenPriceWei; // tokn price in wei

    mapping(address => Backer) public backers; //backer list
    address[] public backersIndex; // to be able to itarate through backers for verification.  



    // @notice to verify if action is not performed out of the campaing range
    modifier respectTimeFrame() {
        require (block.number >= startBlock && block.number <= endBlock);           
        _;
    }

     // @ntice overwrite to ensure that if any money are left, they go 
     // to multisig wallet
     function kill() public {
        if (msg.sender == owner) 
            selfdestruct(multisig);
    }

    // Events
    event ReceivedETH(address backer, uint amount, uint tokenAmount);
    event RefundETH(address backer, uint amount);

    // Crowdsale  {constructor}
    // @notice fired when contract is crated. Initilizes all constant and initial variables.
    function Crowdsale(uint toknesSoldPresale) public {

        multisig = 0xF821Fd99BCA2111327b6a411C90BE49dcf78CE0f; 
        team = 0xF821Fd99BCA2111327b6a411C90BE49dcf78CE0f; 
        tokensForTeam = 27500000e18;  // tokens for the team               
        totalTokensSent = toknesSoldPresale; // initilaize token number sold in presale            
        startBlock = 0; // Should wait for the call of the function start
        endBlock = 0; // Should wait for the call of the function start
        maxCap = 82500000e18; // reserve tokens for the team            
        tokenPriceWei = 1100000000000000; // initialize price of token
        minCap = 4500000e18;  // initilize min cap      
    }


     // @notice to populate website with status of the sale 
    function returnWebsiteData() external view returns(uint, uint, uint, uint, uint, uint, uint, uint, bool, bool) {
    
        return (startBlock, endBlock, numberOfBackers(), ethReceived, maxCap, minCap, totalTokensSent,  tokenPriceWei, stopped, crowdsaleClosed);
    }

    // @notice in case refunds are needed, money can be returned to the contract
    function fundContract() external payable onlyOwner() returns (bool) {
        return true;
    }


    // @notice Specify address of token contract
    // @param _tokenAddress {address} address of the token contract
    // @return res {bool}
    function updateTokenAddress(Token _tokenAddress) external onlyOwner() returns(bool res) {
        token = _tokenAddress;
        return true;
    }



    // @notice return number of contributors
    // @return  {uint} number of contributors
    function numberOfBackers() public view returns(uint) {
        return backersIndex.length;
    }

    // {fallback function}
    // @notice It will call internal function which handels allocation of Ether and calculates amout of tokens.
    function () external payable {           
        contribute(msg.sender);
    }

    // @notice It will be called by owner to start the sale    
    function start(uint _block) external onlyOwner() {   

        require(_block < 216000);  // 2.5*60*24*60 days = 216000  - allow max 60 days for campaign
                                                         
        startBlock = block.number;
        endBlock = safeAdd(startBlock, _block); 
    }

    // @notice Due to changing average of block time
    // this function will allow on adjusting duration of campaign closer to the end 
    function adjustDuration(uint _block) external onlyOwner() {

        require(_block < 288000);  // 2.5*60*24*80 days = 288000     // allow for max of 80 days for campaign
        require(_block > safeSub(block.number, startBlock)); // ensure that endBlock is not set in the past
        endBlock = safeAdd(startBlock, _block); 
    }

    // @notice It will be called by fallback function whenever ether is sent to it
    // @param  _backer {address} address of beneficiary
    // @return res {bool} true if transaction was successful
    function contribute(address _backer) internal stopInEmergency respectTimeFrame returns(bool res) {      

        uint tokensToSend = safeMul(msg.value, 1e18) / tokenPriceWei; // ensure adding of decimal values before devision
        
        totalTokensSent = safeAdd(totalTokensSent, tokensToSend);
        // Ensure that max cap hasn't been reached
        require (totalTokensSent <= maxCap);        

        Backer storage backer = backers[_backer];

         if (backer.weiReceived == 0)      
            backersIndex.push(_backer);

        if (!token.transfer(_backer, tokensToSend)) 
            revert(); // Transfer tokens
        backer.tokensSent = safeAdd(backer.tokensSent, tokensToSend);
        backer.weiReceived = safeAdd(backer.weiReceived, msg.value);
        ethReceived = safeAdd(ethReceived, msg.value); // Update the total Ether recived         

        multisig.transfer(msg.value);   // transfer funds to multisignature wallet             

        ReceivedETH(_backer, msg.value, tokensToSend); // Register event
        return true;
    }




    // @notice This function will finalize the sale.
    // It will only execute if predetermined sale time passed or all tokens are sold.
    function finalize() external onlyOwner() {

        require(!crowdsaleClosed);        
        // purchasing precise number of tokens might be impractical, thus subtract 100 tokens so finalizition is possible
        // near the end 
        require (block.number > endBlock || totalTokensSent >= safeSub(maxCap, 100)); 
        require(totalTokensSent >= minCap);  // ensure that campaign was successful         
                  
        if (!token.transfer(team, token.balanceOf(this))) 
            revert();
        token.unlock();        
        crowdsaleClosed = true;        
    }


    // @notice Failsafe drain
    function drain() external onlyOwner() {
        multisig.transfer(this.balance);      
    }

    // @notice it will allow contributors to get refund in case campaign failed
    function refund()  external stopInEmergency returns (bool) {


        require (block.number > endBlock); // ensure that campaign is over
        require(totalTokensSent < minCap); // ensure that campaign failed
        require(this.balance > 0);  // contract will hold 0 ether at the end of the campaign.                                  
                                    // contract needs to be funded through fundContract() for this action

        Backer storage backer = backers[msg.sender];

        require(backer.weiReceived > 0);           
        require(!backer.refunded);        

        if (!token.burn(msg.sender, backer.tokensSent))
            revert();
        backer.refunded = true;
      
        refundCount ++;
        totalRefunded = safeAdd(totalRefunded,backer.weiReceived);
        msg.sender.transfer(backer.weiReceived);
        RefundETH(msg.sender, backer.weiReceived);
        return true;
    }
   

}

// The PPP token
contract Token is ERC20, SafeMath, Ownable {
    // Public variables of the token
    string public name;
    string public symbol;
    uint8 public decimals; // How many decimals to show.
    string public version = "v0.1";
    uint public initialSupply;
    uint public totalSupply;
    bool public locked;
    address public crowdSaleAddress;
    address public preSaleAddress;       
    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;

    // Lock transfer for contributors during the ICO 
    modifier onlyUnlocked() {
        if (msg.sender != crowdSaleAddress && msg.sender != preSaleAddress && locked) 
            revert();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && msg.sender != crowdSaleAddress ) 
            revert();
        _;
    }

    // The PPP Token created with the time at which the crowdsale ends
    function Token(address _crowdSaleAddress, address _presaleAddress, uint tokensSold) public {
        // Lock the transfCrowdsaleer function during the crowdsale
        locked = true;
        initialSupply = 165000000e18;
        totalSupply = initialSupply;
        name = "PayPie"; // Set the name for display purposes
        symbol = "PPP"; // Set the symbol for display purposes
        decimals = 18; // Amount of decimals for display purposes
        crowdSaleAddress = _crowdSaleAddress;
        preSaleAddress = _presaleAddress;

       
        // Address to hold tokens for pre-sale customers
        balances[_presaleAddress] = tokensSold;

        // Address to hold tokens for public sale customers
        balances[crowdSaleAddress] = totalSupply - balances[_presaleAddress];
    }

    function unlock() public onlyAuthorized {
        locked = false;
    }

    function lock() public onlyAuthorized {
        locked = true;
    }

    function burn( address _member, uint256 _value) public onlyAuthorized returns(bool) {
        balances[_member] = safeSub(balances[_member], _value);
        totalSupply = safeSub(totalSupply, _value);
        Transfer(_member, 0x0, _value);
        return true;
    }

    function transfer(address _to, uint _value) public onlyUnlocked returns(bool) {
        balances[msg.sender] = safeSub(balances[msg.sender], _value);
        balances[_to] = safeAdd(balances[_to], _value);
        Transfer(msg.sender, _to, _value);
        return true;
    }

    
    function transferFrom(address _from, address _to, uint256 _value) public onlyUnlocked returns(bool success) {
        require(_to != address(0));
        require (balances[_from] >= _value); // Check if the sender has enough                            
        require (_value <= allowed[_from][msg.sender]); // Check if allowed is greater or equal        
        balances[_from] = safeSub(balances[_from], _value); // Subtract from the sender
        balances[_to] = safeAdd(balances[_to],_value); // Add the same to the recipient
        allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender],_value);  // decrease allowed amount
        Transfer(_from, _to, _value);
        return true;
    }

    function balanceOf(address _owner) public view returns(uint balance) {
        return balances[_owner];
    }


  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   *
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
    function approve(address _spender, uint _value) public returns(bool) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }


    function allowance(address _owner, address _spender) public view returns(uint remaining) {
        return allowed[_owner][_spender];
    }


    /**
   * approve should be called when allowed[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   */
  function increaseApproval (address _spender, uint _addedValue) public returns (bool success) {
    allowed[msg.sender][_spender] = safeAdd(allowed[msg.sender][_spender], _addedValue);
    Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

  function decreaseApproval (address _spender, uint _subtractedValue) public returns (bool success) {
    uint oldValue = allowed[msg.sender][_spender];
    if (_subtractedValue > oldValue) {
      allowed[msg.sender][_spender] = 0;
    } else {
      allowed[msg.sender][_spender] = safeSub(oldValue, _subtractedValue);
    }
    Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

}