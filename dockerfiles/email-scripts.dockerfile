FROM continuumio/miniconda3:24.1.2-0
RUN apt-get update && apt-get install -y jq
RUN conda install -y pandas=2.2.1 jinja2=3.1.3 pip=24.0
RUN pip install interop==1.3.1 PyYAML==6.0.1
