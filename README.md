# ICOpaypie

# README #



### What is this repository for? 

* PyaPie ICO contracts
* ver 1.0
* for crowd funding during the pre and ICO phase


### How do I get set up? 

### For Presale

* Deploy **Presale** contract. 

### For Public Sale


* First deploy **Crwodsale** contract and obtain its address.  
* Secondly deploy **Token** contract and use address from previous step as its input. Obtain address of the token contract.  
* Thirdly call function **updateTokenAddress()** of **Crowdsale** contract and provide address from Token contract as an input.


### How do I run

* contract owner can start both presale and public sale contracts by calling **start()** function
* contributions are accepted by sending ether to presale or public sale contract address
* when the campaign is over, contract owner can run **finilize()** function to end the campaign and transfer remaining tokens to team address in case of public sale. 
* in case of emergency function **emergencyStop()** can be called to stop contribution and function **release()** to start campaign again. 
* in case of refunds or claiming tokens in presale contract, contract owner needs to set the appropriate status of public campaign.
 function **setMainCampaignStatus()** should be used to set the conditions for refunds or claiming of tokens. 
 Setting state to *true* will allow contributors to claim purchased tokens, *false* will allow them to claim refunds. 
* in case of failed campaign, contract owner will need to fund both contracts so contributors can receive their funds back.
 Function **fundContract()** should be used. 

* in case of failed campaign, contributors can safely withdraw their funds by calling **refund()** function in presale and public sale contracts. 
* in presale contributors will need to claim their tokens after main ICO has ended. To claim tokens one needs to call function **claimTokens()**.
Contract owner will need to set address of the token contract using function **setToken()** and pass token address as parameter. Also **setMainCampaignStatus()** will need to be called with value *true*, indicating that main ICO has been successfull.  

