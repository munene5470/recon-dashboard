FROM golang:1.25-bookworm AS go-runtime

FROM node:20-bookworm-slim AS build
WORKDIR /app

COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-bookworm-slim
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=4000
ENV PATH=/usr/local/go/bin:/usr/local/bin:/root/go/bin:$PATH
ENV GOBIN=/usr/local/bin
ENV GOPATH=/root/go

COPY --from=go-runtime /usr/local/go /usr/local/go

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        curl \
        dnsutils \
        git \
        jq \
        nmap \
        python3 \
        python3-pip \
        python3-venv \
        unzip \
        wget \
        whois \
        whatweb \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN go version && node --version && npm --version

COPY package*.json ./
RUN npm install --omit=dev \
    && npm rebuild sqlite3 --build-from-source

COPY --from=build /app/dist ./dist
COPY --from=build /app/server ./server
COPY --from=build /app/scripts ./scripts
COPY --from=build /app/index.html ./index.html

COPY scripts/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh \
    && /tmp/install-tools.sh

RUN mkdir -p /app/data /app/recon-output

EXPOSE 4000
CMD ["node", "server/index.js"]
