/**
 *Submitted for verification at Etherscan.io on 2022-05-09
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./UUSD-deps.sol";

contract UUSD is Ownable, Pausable, Blacklistable, ERC20 {

    using SafeMath for uint256;

    IERC20 usdcToken;
    IERC20 usdtToken;
    IERC20 daiToken;
    IERC20 waterToken;

    //address private constant USDC_address = address(0x060aD346b830ee4c5CA128d957d17C4D8807Dc11);      // ropsten USDC ADDRESS
    //address private constant DAI_address = address(0x014b42dC75B130b8346759Fe05444aDE61F2FbD1);       // ropsten DAI ADDRESS
    //address private constant USDT_address = address (0xdAC17F958D2ee523a2206206994597C13D831ec7);     // ropsten USDT address
    address private constant FACTORY_CONTRACT = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);    // ropsten
    address private constant UNISWAP_V2_ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);   // ropsten address

    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Factory public uniswapFactory;
    address vault;
    uint256 usdc_balance;
    uint256 usdt_balance;
    uint256 dai_balance;

    mapping(address => bool) whitelist;

    event Mint(address indexed minter, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);
    event AddedToWhitelist(address indexed account);
    event RemovedFromWhitelist(address indexed account);
    event Log(string _message, uint _amount);

    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender));
        _;
    }

    constructor(address _vault, IERC20 _usdt, IERC20 _usdc, IERC20 _dai, IERC20 _water) ERC20("Wrapped USD", "UUSD")  {
        uniswapRouter = IUniswapV2Router02(UNISWAP_V2_ROUTER);
        uniswapFactory = IUniswapV2Factory(FACTORY_CONTRACT);
        vault = _vault;
        usdtToken = _usdt;
        usdcToken = _usdc;
        daiToken = _dai;
        waterToken = _water;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    //Burn UUSD Token
    // OnlyOwner function
    function burnUUSD(uint256 _amount) external onlyOwner {
        _burn(msg.sender,_amount);
    }

    //Buy UUSD using WATER Token
    function buyUUSD(address _token, uint256 _amount) external onlyOwner {
        require(IERC20(_token) == waterToken,"TOKEN IS INVALID");
        ERC20(_token).transferFrom(msg.sender, vault, _amount); // address(this) --> vault
        _mint(msg.sender, _amount);
    }

    function buy(address _token,uint256 _amount) external payable {

        //For stable coins we are minting same amount of tokens
        //For whitelisting users only.
        if(isWhitelisted(_token)){
            ERC20(_token).transferFrom(msg.sender, vault, _amount); // address(this) --> vault
            _mint(msg.sender, _amount);
        }
        else{
            if(msg.value > 0){
                uint256 values  = msg.value;
                uint deadline = block.timestamp + 150;
                address[] memory path = new address[](2);
                path[0] = uniswapRouter.WETH();
                path[1] = address(usdcToken);
                uint[] memory swappedTokenAmount = uniswapRouter.swapETHForExactTokens{value:values}(_amount, path, vault, deadline); // address(this) --> vault
                _mint(msg.sender, swappedTokenAmount[1]);

                (bool success,) = msg.sender.call{ value: address(this).balance }("");
                require(success, "refund failed");
            }
            else{
                uint swappedTokenAmount = swap(_token,_amount);
                _mint(msg.sender, swappedTokenAmount);
            }

        }
    }

    function swap(address _swapToken,uint256 _amountIn) internal returns(uint){

        address pair1 = uniswapFactory.getPair(_swapToken, address(usdcToken)); //check pair with US
        if(pair1!= address(0)){
            uint deadline = block.timestamp + 250;
            address[] memory path = new address[](2);
            path[0] = _swapToken;
            path[1] = address(usdcToken);
            IERC20(_swapToken).transferFrom(msg.sender,address(this),_amountIn);
            IERC20(_swapToken).approve(UNISWAP_V2_ROUTER,_amountIn);
            uint[] memory result = uniswapRouter.swapTokensForExactTokens(_amountIn, 0, path, vault, deadline); // address(this) --> vault
            return result[1];


        }else{
            uint deadline = block.timestamp + 150;
            address[] memory path = new address[](2);
            path[0] = _swapToken;
            path[1] = address(daiToken);
            IERC20(_swapToken).transferFrom(msg.sender,address(this),_amountIn);
            IERC20(_swapToken).approve(UNISWAP_V2_ROUTER,_amountIn);
            uint[] memory result = uniswapRouter.swapTokensForExactTokens(_amountIn, 0, path, vault, deadline); // address(this) --> vault
            return result[1];
        }
    }


    // USDC-USDT
    // USDC-DAI
    // USDT-DAI
    function settleAmount() external onlyOwner {
        usdc_balance = usdcToken.balanceOf(vault);
        usdt_balance = usdtToken.balanceOf(vault);
        dai_balance = daiToken.balanceOf(vault);

        usdcToken.approve(UNISWAP_V2_ROUTER, usdc_balance);
        usdtToken.approve(UNISWAP_V2_ROUTER, usdt_balance);
        daiToken.approve(UNISWAP_V2_ROUTER, dai_balance);

        //require(checkAllPairs(address(usdcToken), address(usdtToken), address(daiToken)),"Pair of Token is not possible");
        (uint256 _amountA, uint256 _amountB, uint256 _LPAmountA) = uniswapRouter.addLiquidity(
            address(usdcToken),
            address(usdtToken),
            usdc_balance,
            usdt_balance,
            1,
            1,
            vault, // address(this) --> vault
            block.timestamp + 150
        );

        emit Log("amount", _amountA);
        emit Log("amount", _amountB);
        emit Log("liquidity", _LPAmountA);

        (uint256 _amountC, uint256 _amountD, uint256 _LPAmountC) = uniswapRouter.addLiquidity(
            address(usdcToken),
            address(daiToken),
            usdc_balance,
            dai_balance,
            1,
            1,
            vault, // address(this) --> vault
            block.timestamp + 150
        );

        emit Log("amount", _amountC);
        emit Log("amount", _amountD);
        emit Log("liquidity", _LPAmountC);

        (uint256 _amountE, uint256 _amountF, uint256 _LPAmountE) = uniswapRouter.addLiquidity(
            address(usdtToken),
            address(daiToken),
            usdt_balance,
            dai_balance,
            1,
            1,
            vault,  // address(this) --> vault
            block.timestamp + 150
        );

        emit Log("amount", _amountE);
        emit Log("amount", _amountF);
        emit Log("liquidity", _LPAmountE);
    }

    function removeLiquidity(address _tokenA, address _tokenB) external onlyOwner {
        address pair = uniswapFactory.getPair(_tokenA, _tokenB);

        uint liquidity = IERC20(pair).balanceOf(address(this));
        IERC20(pair).approve(UNISWAP_V2_ROUTER, liquidity);

        (uint amountA, uint amountB) =
        uniswapRouter.removeLiquidity(
            _tokenA,
            _tokenB,
            liquidity,
            1,
            1,
            vault,
            block.timestamp
        );

        emit Log("amountA", amountA);
        emit Log("amountB", amountB);
    }

    //_USDC_address = USDC
    //_DAI_address = USDT
    //_token3 = DAI
    // function checkAllPairs(address _USDC_address, address _DAI_address, address _token3) internal returns(bool){
    //     address _tokenPair1 = uniswapFactory.getPair(_USDC_address,_DAI_address);
    //     address _tokenPair2 = uniswapFactory.getPair(_USDC_address,_token3);
    //     address _tokenPair3 = uniswapFactory.getPair(_DAI_address,_token3);
    //     if(_tokenPair1 == address(0)){
    //         _tokenPair1 = uniswapFactory.createPair(_USDC_address, _DAI_address); //USDC - USDT
    //     }if(_tokenPair2 == address(0)){
    //         _tokenPair2 = uniswapFactory.createPair(_USDC_address, _token3); //USDC - DAI
    //     }if(_tokenPair3 == address(0)){
    //         _tokenPair3 = uniswapFactory.createPair(_DAI_address, _token3); //USDT - DAI
    //     }
    //     return true;
    // }

    function setVaultAddress(address _vault) external onlyOwner returns(bool){
        vault = _vault;
        return true;
    }

    function burn(uint _amount) external payable{
        checkBalance(_amount);
        //payable(msg.sender).transfer(_amount);
        _burn(msg.sender, _amount);
    }

    function checkBalance(uint256 _amount) internal {
        uint256 equalReturnAmount = _amount.mul(33).div(100);
        uint256 fiftyFiftyReturnAmount = _amount.mul(50).div(100);
        if((usdcToken.balanceOf(vault) > equalReturnAmount && (usdtToken.balanceOf(vault) > equalReturnAmount) && (daiToken.balanceOf(vault) > equalReturnAmount))){
            usdcToken.transferFrom(vault, msg.sender, equalReturnAmount);
            usdtToken.transferFrom(vault, msg.sender, equalReturnAmount);
            daiToken.transferFrom(vault, msg.sender, equalReturnAmount);

        }else if((usdcToken.balanceOf(vault) < equalReturnAmount) && (usdtToken.balanceOf(vault) > equalReturnAmount) && (daiToken.balanceOf(vault) > equalReturnAmount)){

            usdtToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);
            daiToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);


        }else if((usdcToken.balanceOf(vault) > equalReturnAmount) && (usdtToken.balanceOf(vault) < equalReturnAmount) && (daiToken.balanceOf(vault) > equalReturnAmount)){
            usdcToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);
            daiToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);


        }else if((usdcToken.balanceOf(vault) > equalReturnAmount) && (usdtToken.balanceOf(vault) > equalReturnAmount) && (daiToken.balanceOf(vault) < equalReturnAmount)){
            usdtToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);
            usdcToken.transferFrom(vault, msg.sender, fiftyFiftyReturnAmount);


        }else if((usdcToken.balanceOf(vault) < equalReturnAmount) && (usdtToken.balanceOf(vault) < equalReturnAmount) && (daiToken.balanceOf(vault) > equalReturnAmount)){
            daiToken.transferFrom(vault, msg.sender, _amount);


        }else if((usdcToken.balanceOf(vault) < equalReturnAmount) && (usdtToken.balanceOf(vault) > equalReturnAmount) && (daiToken.balanceOf(vault) < equalReturnAmount)){
            usdtToken.transferFrom(vault, msg.sender, _amount);


        }else if((usdcToken.balanceOf(vault) > equalReturnAmount) && (usdtToken.balanceOf(vault) < equalReturnAmount) && (daiToken.balanceOf(vault) < equalReturnAmount)){
            usdcToken.transferFrom(vault, msg.sender, _amount);


        }

    }

    function add(address _address) public onlyOwner {
        whitelist[_address] = true;
        emit AddedToWhitelist(_address);
    }

    function remove(address _address) public onlyOwner {
        whitelist[_address] = false;
        emit RemovedFromWhitelist(_address);
    }

    function isWhitelisted(address _address) public view returns(bool) {
        return whitelist[_address];
    }


    function withdraw(address _recipient) public payable onlyOwner {
        payable(_recipient).transfer(address(this).balance);
    }

    receive() payable  external {}




}