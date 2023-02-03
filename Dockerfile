FROM bytewax/bytewax:latest-python3.9

ENV PYTHONUNBUFFERED 1

WORKDIR /flow

COPY . .

RUN pip install -r requirements.txt

ENTRYPOINT ["python", "dataflow.py"]
