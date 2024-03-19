# Real-Time Financial Exchange Order Book Application

- Skill level
    
    **Beginner, no prior knowledge requirements**
    
- Time to complete
    
    **Approx. 25 min**
    
In this example we are going to walk through how you can maintain a limit order book in real-time with very little extra infrastructure with Bytewax.

We are going to:
* Connect to Coinbase via WebSockets for live order book updates.
* Initialize order books with current snapshots for major cryptocurrencies.
* Update order books in real-time with market changes.
* Utilize advanced data structures for efficient order book management.
* Process live data with Bytewax to maintain and summarize order books.
* Filter updates for significant market movements based on spread.

## ****Prerequisites****

**Python modules**
bytewax==0.18.*
websocket-client

## Your Takeaway

*At the end of this tutorial you will understand how to use Bytewax to analyze financial exchange data. You will learn to establish connections to a WebSocket for real-time data, use Bytewax's operators to efficiently manage an order book, and apply analytical techniques to assess trading opportunities based on the dynamics of buy and sell orders.*

## Table of contents

- Resources
- Concepts
- Websocket Input
- Constructing the Dataflow
- Output
- Execution
- Summary

## Resources

[Github link](https://github.com/bytewax/crypto-orderbook-app)

## Concepts

To start off, we are going to diverge into some concepts around markets, exchanges and orders.

**Order Book**

A Limit Order Book, or just Order Book is a record of all limit orders that are made. A limit order is an order to buy (bid) or sell (ask) an asset for a given price. This could facilitate the exchange of dollars for shares or, as in our case, they could be orders to exchange crypto currencies. On exchanges, the limit order book is constantly changing as orders are placed every fraction of a second. The order book can give a trader insight into the market, whether they are looking to determine liquidity, to create liquidity, design a trading algorithm or determine when bad actors are trying to manipulate the market.

**Bid and Ask**

In the order book, the **ask price** is the lowest price that a seller is willing to sell at and the **bid price** is the highest price that a buyer is willing to buy at. A limit order is different than a market order in that the limit order can be placed with generally 4 dimensions, the direction (buy/sell), the size, the price and the duration (time to expire). A market order, in comparison, has 2 dimensions, the direction and the size. It is up to the exchange to fill a market order and it is filled via what is available in the order book.

**Level 2 Data**

An exchange will generally offer a few different tiers of information that traders can subscribe to. These can be quite expensive for some exchanges, but luckily for us, most crypto exchanges provide access to the various levels for free! For maintaining our order book we are going to need at least level2 order information. This gives us granularity of each limit order so that we can adjust the book in real-time. Without the ability to maintain our own order book, the snapshot would be almost instantly out of date and we would not be able to act with perfect information. We would have to download the order book every millisecond, or faster, to stay up to date and since the order book can be quite large, this isn't really feasible.

Alright, let's get started!

## ****Websocket Input****

Our goal is to build a scalable system that can monitor multiple cryptocurrency pairs across different workers in real time. We are going to build an asynchronous function that will connect to the Coinbase Pro websocket and then stream the data to our dataflow. We will use the `websockets` Python library to connect to the websocket and then we will use the `bytewax` library to stream the data to our dataflow.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L9-L27

Now that we have our websocket based data generator built, we will our dataflow. Since we're using a `StatelessSource`, we'll create a `DynamicInput` subclass called `CoinbaseInput`. An instance of `CoinbaseInput` will be constructed on each worker. In the `build` method, we receive information about which worker we are: `worker_index` and the total number of workers (`worker_count`). We have added some custom code in order to distribute the currency pairs with the logic. It should be noted that if you run more than one worker with only one currency pair, the other workers will not be used.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L30-L40

## Constructing The Dataflow

Before we get to the exciting part of our order book dataflow, we need to create our Dataflow object and prep the data. We'll start with creating an empty `Dataflow` object and add the `CoinbaseSource` we created above.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L43-L44

Now that we have input for our Dataflow, we will specify some of the operations we want performed on our data. A `map` step is a one-to-one transformation step. The first `map` step will deserialize the JSON we are receiving from the websocket into a Python dictionary. Once deserialized, we can reformat the data to be a tuple of the shape (product_id, data). This will permit us to aggregate by the product_id as our key in the next step.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L46-L55

Now for the exciting part. The code below is what we are using to:
1. Construct the orderbook as two dictionaries, one for asks and the other for bids.
2. Assign a value to the ask and bid price.
3. For each new order, update the order book and then update the bid and ask prices where required.
4. Return bid and ask price, the respective volumes of the ask and the difference between the prices.

The data from the coinbase pro websocket is first a snapshot of the current order book in the format:

```json
{
  "type": "snapshot",
  "product_id": "BTC-USD",
  "bids": [["10101.10", "0.45054140"]...],
  "asks": [["10102.55", "0.57753524"]...]
}
```

  and then each additional message is an update with a new limit order of the format:

```json
{
  "type": "l2update",
  "product_id": "BTC-USD",
  "time": "2019-08-14T20:42:27.265Z",
  "changes": [
    [
      "buy",
      "10101.80000000",
      "0.162567"
    ]
  ]
}
```

This flow of receiving a snapshot followed by real-time updates works well for our scenario with respect to recovery. In the instance that we lose our connection to Coinbase, we will not need to worry about recovery and we can resume from the initial snapshot.

To maintain an order book in real time, we will first need to construct an object to hold the orders from the snapshot and then update that object with each additional update. This is a good use case for the [`stateful_map`](https://staging.bytewax.io/apidocs/bytewax.dataflow#bytewax.dataflow.Dataflow.stateful_map) operator, which can aggregate data by a key. `stateful_map` requires two functions: a `builder` that builds the initial, empty state when a new key is encountered, and a `mapper` that combines new items into the existing state.

Below we have the code for the OrderBook object that has a bids and asks dictionary. These will be used to first create the order book from the snapshot and once created we can attain the first bid price and ask price. The bid price is the highest buy order placed and the ask price is the lowest sell order places. Once we have determined the bid and ask prices, we will be able to calculate the spread and track that as well.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L58-L129

With our snapshot processed, for each new message we receive from the websocket, we can update the order book the bid and ask price and the spread via the `update_orderbook` method. Sometimes an order was filled or it was cancelled and in this case what we receive from the update is something similar to `'changes': [['buy', '36905.39', '0.00000000']]`. When we receive these updates of size `'0.00000000'`, we can remove that item from our book and potentially update our bid and ask price. The code below will check if the order should be removed and if not it will update the order. If the order was removed, it will check to make sure the bid and ask prices are modified if required.

Finishing it up, for fun we can filter for a spread as a percentage of the ask price greater than 0.1% and then capture the output. Maybe we can profit off of this spread... or maybe not.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L130-L132

## **Output**

We have successfully created a websocket connection, built our orderbook and then analyzed the order book, filtering down to the important spreads. The final steps are to configure some output and to run it. We will use the `output` operator, with the built-in `StdOutput` class to write to standard out.

https://github.com/bytewax/crypto-orderbook-app/blob/049229fa01184127658d40d3b47638232038371b/dataflow.py#L134

## **Executing the Dataflow**

Now we can run our completed dataflow:

``` bash
> python -m bytewax.run dataflow:flow
```

Eventually, if the spread is greater than $5, we will see some output similar to what is below.

```bash
{"type":"subscriptions","channels":[{"name":"level2","product_ids":["BTC-USD"]}]}
('BTC-USD', (38590.1, 0.00945844, 38596.73, 0.01347429, 6.630000000004657))
('BTC-USD', (38590.1, 0.00945844, 38597.13, 0.02591147, 7.029999999998836))
('BTC-USD', (38590.1, 0.00945844, 38597.13, 0.02591147, 7.029999999998836))
```

## Summary

That's it! You've learned how to use websockets with Bytewax and how to leverage stateful map to maintain the state in a streaming application.

### We want to hear from you!

We would love to see if you can build on this example. Feel free to share what you've built in our [community slack channel](https://join.slack.com/t/bytewaxcommunity/shared_invite/zt-vkos2f6r-_SeT9pF2~n9ArOaeI3ND2w).

See our full gallery of tutorials →

[Share your tutorial progress!](https://twitter.com/intent/tweet?text=I%27m%20mastering%20data%20streaming%20with%20%40bytewax!%20&url=https://bytewax.io/tutorials/&hashtags=Bytewax,Tutorials)
