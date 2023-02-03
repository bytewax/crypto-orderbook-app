FROM bytewax/bytewax:latest-python3.10

ENV PYTHONUNBUFFERED 1

COPY . .

RUN pip install -r requirements.txt

ENTRYPOINT ["python", "dataflow.py"]
