# Start from a debian slim with python support
FROM python:3.11-slim-bullseye
# Setup a workdir where we can put our dataflow
WORKDIR /bytewax
# Install bytewax and the dependencies you need here
RUN pip install bytewax==0.19 websockets
# Copy the dataflow in the workdir
COPY dataflow.py dataflow.py
# And run it.
# Set PYTHONUNBUFFERED to any value to make python flush stdout,
# or you risk not seeing any output from your python scripts.
ENV PYTHONUNBUFFERED 1
CMD ["python", "-m", "bytewax.run", "dataflow"]