# Etapa 1: Compilar Ruby e instalar dependências
FROM debian:bookworm-slim AS builder

ARG NODE_VERSION=18

# Instalar dependências essenciais
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libssl-dev \
      libreadline-dev \
      zlib1g-dev \
      libxml2-dev \
      libxslt-dev \
      libpq-dev \
      libvips42 \
      curl \
      git \
      ca-certificates \
      python3 \
      gnupg \
      libcurl4 \
      libyaml-dev && \
    rm -rf /var/lib/apt/lists/*

# Baixar e compilar Ruby 3.3.3
WORKDIR /usr/src/ruby
RUN curl -fsSL https://cache.ruby-lang.org/pub/ruby/3.3/ruby-3.3.3.tar.gz  | tar -xz && \
    cd ruby-3.3.3 && \
    ./configure --disable-install-doc && \
    make && \
    make install && \
    cd .. && \
    rm -rf ruby-3.3.3

# Instalar bundler específico usado no projeto
WORKDIR /app
COPY Gemfile.lock Gemfile ./

RUN gem install bundler -v "$(grep -A1 'BUNDLED WITH' Gemfile.lock | tail -n1 | tr -d ' \r')" && \
    bundle config set path 'vendor/bundle' && \
    bundle config set deployment true && \
    bundle config set without 'development test' && \
    bundle install --retry 3 --jobs $(nproc)

# Instalar Node.js e Yarn
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x  | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    npm cache clean --force && \
    rm -rf /tmp/npm*

# Copiar código e pacotes JS
COPY package.json yarn.lock ./
RUN yarn install --check-files --frozen-lockfile

# Copiar todo o app e compilar assets
COPY . ./

RUN RAILS_ENV=production bundle exec rake assets:precompile

# Limpar arquivos desnecessários
RUN rm -rf tmp/* log/* vendor/bundle/ruby/3.3.0/cache/*.gem

# Etapa Final: Imagem Enxuta
FROM debian:bookworm-slim

ARG NODE_VERSION=18

# Dependências mínimas em runtime
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libpq5 \
      libvips42 \
      ca-certificates \
      nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar apenas o necessário do stage anterior
COPY --from=builder /usr/local/bin/ruby /usr/local/bin/ruby
COPY --from=builder /usr/local/bin/gem /usr/local/bin/gem
COPY --from=builder /usr/local/bin/bundle /usr/local/bin/bundle
COPY --from=builder /usr/local/lib/ruby /usr/local/lib/ruby
COPY --from=builder /app /app

# Garantir PATH correto
ENV PATH="/usr/local/bin:$PATH"

# Expondo porta e definindo comando inicial
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
