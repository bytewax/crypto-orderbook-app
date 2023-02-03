# Real-time Financial Exchange Order Book Application

- Skill level
    
    **Beginner, no prior knowledge requirements**
    
- Time to complete
    
    **Approx. 25 min**
    

In this example we are going to walk through how you can maintain a limit order book in real-time with very little extra infrastructure with Bytewax.

We are going to:
* Use websockets to connect to an exchange (coinbase)
* Setup an order book using a snapshot
* Update the order book in real-time
* Use algorithms to trade crypto currencies and profit. Just kidding, this is left to an exercise for the reader.

To start off, we are going to diverge into some concepts around markets, exchanges and orders.

## ****Prerequisites****

**Python modules**
websocket-client

## Your Takeaway

*At the end of this tutorial users will understand how to use Bytewax to analyze financial exchange data by connecting to a websocket and using Bytewax operators to maintain an order book and analyzing the orders.*

## Table of content

- Resources
- Concepts
- Websocket Input
- Constructing the Dataflow
- Output
- Execution
- Summary

## Resources

Github link

## Concepts

**Order Book**

A Limit Order Book, or just Order Book is a record of all limit orders that are made. A limit order is an order to buy (bid) or sell (ask) an asset for a given price. This could facilitate the exchange of dollars for shares or, as in our case, they could be orders to exchange crypto currencies. On exchanges, the limit order book is constantly changing as orders are placed every fraction of a second. The order book can give a trader insight into the market, whether they are looking to determine liquidity, to create liquidity, design a trading algorithm or maybe determine when bad actors are trying to manipulate the market.

**Bid and Ask**

In the order book, the **ask price** is the lowest price that a seller is willing to sell at and the **bid price** is the highest price that a buyer is willing to buy at. A limit order is different than a market order in that the limit order can be placed with generally 4 dimensions, the direction (buy/sell), the size, the price and the duration (time to expire). A market order, in comparison, has 2 dimensions, the direction and the size. It is up to the exchange to fill a market order and it is filled via what is available in the order book.

**Level 2 Data**

An exchange will generally offer a few different tiers of information that traders can subscribe to. These can be quite expensive for some exchanges, but luckily for us, most crypto exchanges provide access to the various levels for free! For maintaining our order book we are going to need at least level2 order information. This gives us granularity of each limit order so that we can adjust the book in real-time. Without the ability to maintain our own order book, the snapshot would get almost instantly out of date and we would not be able to act with perfect information. We would have to download the order book every millisecond, or faster, to stay up to date and since the order book can be quite large, this isn't really feasible.

Alright, let's get started!

## ****Websocket Input****

We are going to eventually create a cluster of dataflows where we could have multiple currency pairs running in parallel on different workers. To start, we will build a websocket input function that will be able to handle multiple workers. The input will use the coinbase pro websocket url (`wss://ws-feed.pro.coinbase.com`) and the Python websocket library to create a connection. Once connected we can send a message to the websocket subscribing to product_ids (pairs of currencies - USD-BTC for this example) and channels (level2 order book data). Finally since we know there will be some sort of acknowledgement message we can grab that with `ws.recv()` and print it out.

https://github.com/bytewax/crypto-orderbook-app/blob/e3dbb71986184a0c855b92f4726aaaa9246161c6/dataflow.py#L7-L24

For testing purposes, if you don't want to perform HTTP requests, you can read the sample websocket data from a local file with a list of JSON responses.

```python
def ws_input(product_ids, state):
    print(
        '{"type":"subscriptions","channels":[{"name":"level2","product_ids":["BTC-USD","ETH-USD"]}]}'
    )
    for msg in open("crypto-sockets.json"):
        yield state, msg
```

Now that we have our websocket based data generator built, we will write an input builder for our dataflow. Since we're using a manual input builder, we'll pass a `ManualInputConfig` as our `input` with the builder as a parameter. The input builder is called on each worker and the function will have information about the `worker_index` and the total number of workers (`worker_count`). In this case we are designing our input builder to handle multiple workers and multiple currency pairs, so that we can parallelize the input. So we will distribute the currency pairs with the logic in the code below. It should be noted that if you run more than one worker with only one currency pair, the other workers will not be used.

https://github.com/bytewax/crypto-orderbook-app/blob/e3dbb71986184a0c855b92f4726aaaa9246161c6/dataflow.py#L27-L39

## Constructing The Dataflow

Before we get to the exciting part of our order book dataflow we need to create our dataflow object and prep the data. We start with creating the dataflow object, specifying the input we built above and then we will add two map operators. The first will deserialize the JSON we are receiving from the websocket into a dictionary. Once deserialized, we can reformat the data to be a tuple of the shape (product_id, data). This will permit us to aggregate by the product_id as our key in the next step.

https://github.com/bytewax/crypto-orderbook-app/blob/58b21fcd925d63e3d7af56b1733c0ce9ab5ec08e/dataflow.py#L42-L48

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

This flow of snapshot followed by real-time updates works well for our scenario with respect to recovery. In the instance that we lose connection, we will not need to worry about recovery and we can resume from the initial snapshot.

To maintain an order book in real time, we will first need to construct an object to hold the orders from the snapshot and then update that object with each additional update. This is a good use case for the [`stateful_map`](/apidocs#bytewax.Dataflow.stateful_map) operator, which can aggregate by key. `Stateful_map` will aggregate data based on a function (mapper), into an object that you define. The object must be defined via a builder, because it will create a new object via this builder for each new key received. The mapper must return the object so that it can be updated.

Below we have the code for the OrderBook object that has a bids and asks dictionary. These will be used to first create the order book from the snapshot and once created we can attain the first bid price and ask price. The bid price is the highest buy order placed and the ask price is the lowest sell order places. Once we have determined the bid and ask prices, we will be able to calculate the spread and track that as well.

```python
class OrderBook:
    def __init__(self):
        # if using Python < 3.7 need to use OrderedDict here
        self.bids = {}
        self.asks = {}

    def update(self, data):
        if self.bids == {}:
            self.bids = {float(price): float(size) for price, size in data["bids"]}
            # The bid_price is the highest priced buy limit order.
            # since the bids are in order, the first item of our newly constructed bids
            # will have our bid price, so we can track the best bid
            self.bid_price = next(iter(self.bids))
        if self.asks == {}:
            self.asks = {float(price): float(size) for price, size in data["asks"]}
            # The ask price is the lowest priced sell limit order.
            # since the asks are in order, the first item of our newly constructed
            # asks will be our ask price, so we can track the best ask
            self.ask_price = next(iter(self.asks))
        else:
            # We receive a list of lists here, normally it is only one change,
            # but could be more than one.
            for update in data["changes"]:
                price = float(update[1])
                size = float(update[2])
            if update[0] == "sell":
                # first check if the size is zero and needs to be removed
                if size == 0.0:
                    try:
                        del self.asks[price]
                        # if it was the ask price removed,
                        # update with new ask price
                        if price <= self.ask_price:
                            self.ask_price = min(self.asks.keys())
                    except KeyError:
                        # don't need to add price with size zero
                        pass
                else:
                    self.asks[price] = size
                    if price < self.ask_price:
                        self.ask_price = price
            if update[0] == "buy":
                # first check if the size is zero and needs to be removed
                if size == 0.0:
                    try:
                        del self.bids[price]
                        # if it was the bid price removed,
                        # update with new bid price
                        if price >= self.bid_price:
                            self.bid_price = max(self.bids.keys())
                    except KeyError:
                        # don't need to add price with size zero
                        pass
                else:
                    self.bids[price] = size
                    if price > self.bid_price:
                        self.bid_price = price
        return self, {
            "bid": self.bid_price,
            "bid_size": self.bids[self.bid_price],
            "ask": self.ask_price,
            "ask_price": self.asks[self.ask_price],
            "spread": self.ask_price - self.bid_price,
        }


flow.stateful_map("order_book", OrderBook, OrderBook.update)
```

With our snapshot processed, for each new message we receive from the websocket, we can update the order book, the bid and ask price and the spread via the `update` method. Sometimes an order was filled or it was cancelled and in this case what we receive from the update is something similar to `'changes': [['buy', '36905.39', '0.00000000']]`. When we receive these updates of size `'0.00000000'`, we can remove that item from our book and potentially update our bid and ask price. The code below will check if the order should be removed and if not it will update the order. If the order was removed, it will check to make sure the bid and ask prices are modified if required.

Finishing it up, for fun we can filter for a spread as a percentage of the ask price greater than 01% and then capture the output. Maybe we can profit off of this spread... or maybe not.

The `capture` operator is designed to use the output builder function that we defined earlier. In this case it will print out to our terminal.

```python
flow.filter(lambda x: x[-1]["spread"] / x[-1]["ask"] > 0.0001)
```

## **Output**

We have successfully created a websocket connection, built our orderbook and then analyzed the order book, filtering down to the important spreads. The final steps are to configure some output and to run it. We will use the `capture` operator, with a built in output mechanism to write to standard out.

https://github.com/bytewax/crypto-orderbook-app/blob/e3dbb71986184a0c855b92f4726aaaa9246161c6/dataflow.py#L122-L124

## **Executing the Dataflow**
[Bytewax provides a few different entry points for executing a dataflow](/docs/getting-started/execution/). In this example, we are using the `spawn_cluster` method. What this will do is create the number of worker threads and processes as described. This will create a separate websocket connection for each worker in this scenario because of the nature of websockets and the ability to parallelize them. 

https://github.com/bytewax/crypto-orderbook-app/blob/e3dbb71986184a0c855b92f4726aaaa9246161c6/dataflow.py#L126-L127

Now we can build the Dockerfile and run the dataflow in a docker container with multiple processes. 

https://github.com/bytewax/crypto-orderbook-app/blob/58b21fcd925d63e3d7af56b1733c0ce9ab5ec08e/Dockerfile#L1-L9

Eventually, if the spread is greater than $5, we will see some output similar to what is below.

```bash
{"type":"subscriptions","channels":[{"name":"level2","product_ids":["BTC-USD"]}]}
('BTC-USD', (38590.1, 0.00945844, 38596.73, 0.01347429, 6.630000000004657))
('BTC-USD', (38590.1, 0.00945844, 38597.13, 0.02591147, 7.029999999998836))
('BTC-USD', (38590.1, 0.00945844, 38597.13, 0.02591147, 7.029999999998836))
```

That's it!

We would love to see if you can build on this example. Feel free to share what you've built in our [community slack channel](https://join.slack.com/t/bytewaxcommunity/shared_invite/zt-vkos2f6r-_SeT9pF2~n9ArOaeI3ND2w).

## Summary

That’s it, you are awesome and we are going to rephrase our takeaway paragraph

## We want to hear from you!

If you have any trouble with the process or have ideas about how to improve this document, come talk to us in the #troubleshooting Slack channel!

## Where to next?

- Relevant explainer video
- Relevant case study
- Relevant blog post
- Another awesome tutorial

See our full gallery of tutorials →

[Share your tutorial progress!](https://twitter.com/intent/tweet?text=I%27m%20mastering%20data%20streaming%20with%20%40bytewax!%20&url=https://bytewax.io/tutorials/&hashtags=Bytewax,Tutorials)
