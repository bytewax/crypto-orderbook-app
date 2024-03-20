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
bytewax==0.19
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

Our goal is to build a scalable system that can monitor multiple cryptocurrency pairs across different workers in real time. By crafting an asynchronous function to connect to the Coinbase Pro WebSocket, we facilitate streaming of cryptocurrency data into our dataflow. This process involves the `websockets` Python library for WebSocket connections and `bytewax` for dataflow integration.

The function `_ws_agen` inputs cryptocurrency pair identifiers (e.g., `["BTC-USD", "ETH-USD"]`), establishing a connection to Coinbase Pro's WebSocket. It subscribes to the `level2_batch` channel for live order book updates, sending a JSON subscription message and awaiting a confirmation response with `ws.recv()`.

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L15-L31

To efficiently process and manage this data, we implement the `CoinbasePartition` class, extending Bytewax's `StatefulSourcePartition`. This enables us to obtain the current orderbook at the beginning of the stream when we subscribe.

Within `CoinbasePartition`, `_ws_agen` is used for data fetching through `self._batcher` - in the code we specify batching incoming data every 0.5 seconds or upon receiving 100 messages, optimizing data processing and state management. This structure ensures an efficient, scalable, and fault-tolerant system for real-time cryptocurrency market monitoring.

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L34-L44

In this section we defined the key building blocks to enable asynchronous WebSocket connections and efficient data processing. Before we can establish a dataflow to maintain the order book, we need to define the data classes - this will enable a structured approach to data processing and management. Let's take a look at this in the next section. 

## Defining data classes

Through the Python `dataclasses` library we can establish a structured approach to data processing and management. This is particularly useful for maintaining the order book, as it allows us to define the structure of the data we are working with. As part of this approach we define three data classes:

* `CoinbaseSource`: Serves as a source for partitioning data based on cryptocurrency product IDs. It is crucial for organizing and distributing the data flow across multiple workers, facilitating parallel processing of cryptocurrency pairs.

* `OrderBookSummary`: Summarizes the state of an order book at a point in time, encapsulating the bid and ask prices, sizes, and the spread. This class is immutable (`frozen=True`), ensuring that each instance is a snapshot that cannot be altered, which is essential for accurate historical analysis and decision-making.

* `OrderBookState`: Maintains the current state of the order book, including all bids and asks. It allows for dynamic updates as new market data arrives, keeping track of the best bid and ask prices and their respective sizes.

We can see the implementation of these data classes in the code below:

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L46-L142

In this section, we have defined the data classes that will enable us to maintain the order book in real time. These classes will be used to structure the data flow and manage the state of the order book. Now that we have defined the data classes, we can proceed to construct the dataflow to maintain the order book.

## Constructing The Dataflow

Before we get to the exciting part of our order book dataflow, we need to create our Dataflow object and prep the data. We'll start with creating a `Dataflow` named `'orderbook'`. Once this is initialized, we can incorporate an input data source into the data flow. We can do this by using the `bytewax` module `operator` imported as `op`. We will use `op.input`, specify its input id as `input`, pass the `'orderbook'` dataflow along with the data source - in this case the source of data is the `CoinbaseSource` class we defined earlier initialized with the ids `["BTC-USD", "ETH-USD", "BTC-EUR", "ETH-EUR"]`.

The resulting initialization and data structure output looks as follows:

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L145-L154

Now that we have input for our Dataflow, we will establish a dataflow pipeline for processing live cryptocurrency order book updates. We will focus on analysis and data filtration based on order book spreads. Our goal is for the pipeline to extract and highlight trading opportunities through the analysis of spreads. Let's take a look at key components of the dataflow pipeline:

The `mapper ` function updates and summarizes the order book state, ensuring its an `OrderBookState` object and applying new data updates. The result is a state-summary tuple with key metrics like the best bid and ask prices, sizes, and the spread. We can then use `op.stateful_map` on our `'order_book'` dataflow to apply the `mapper` function to each incoming data batch.

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L157-L166

The last step is to filter the summaries by spread percentage, with a focus on identifying significant spreads greater than 0.1% of the ask price - we will use this as a proxy for trading opportunities. We will define the function and use `op.filter` to apply the filter to summaries from the `'order_book'` dataflow.

https://github.com/bytewax/crypto-orderbook-app/blob/b61e9101cbf11dcb05209ffc6c585148fddea312/dataflow.py#L170-L176


## **Executing the Dataflow**

Now we can run our completed dataflow:

``` bash
> python -m bytewax.run dataflow:flow
```

This will process real-time order book data for three cryptocurrency pairs: BTC-USD, ETH-EUR, and ETH-USD. Each summary provided detailed insights into the bid and ask sides of the market, including prices and sizes.

```bash
('BTC-EUR', OrderBookSummary(bid_price=60152.78, bid_size=0.0104, ask_price=60173.35, ask_size=0.02238611, spread=20.56999999999971))
('BTC-USD', OrderBookSummary(bid_price=65677.38, bid_size=0.05, ask_price=65368.71, ask_size=0.001663, spread=-308.67000000000553))
('ETH-EUR', OrderBookSummary(bid_price=3095.16, bid_size=0.20712451, ask_price=3079.9, ask_size=0.14696149, spread=-15.259999999999764))
```

## Summary

That's it! You've learned how to use websockets with Bytewax and how to leverage stateful map to maintain the state in a streaming application.

### We want to hear from you!

We would love to see if you can build on this example. Feel free to share what you've built in our [community slack channel](https://join.slack.com/t/bytewaxcommunity/shared_invite/zt-vkos2f6r-_SeT9pF2~n9ArOaeI3ND2w).

See our full gallery of tutorials →

[Share your tutorial progress!](https://twitter.com/intent/tweet?text=I%27m%20mastering%20data%20streaming%20with%20%40bytewax!%20&url=https://bytewax.io/tutorials/&hashtags=Bytewax,Tutorials)
