FROM python:3.11-slim-bookworm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=helmet-media-apt rm -f /etc/apt/apt.conf.d/docker-clean && sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources && apt-get -o Acquire::Retries=3 update && apt-get -o Acquire::Retries=3 install -y --no-install-recommends ffmpeg libgomp1 ca-certificates && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir sherpa-onnx==1.12.40 numpy==2.2.6 soundfile==0.13.1
COPY server.py /app/server.py
COPY synthesize.py /app/synthesize.py
CMD ["python", "/app/server.py"]
