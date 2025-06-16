# Etapa 1: Builder com dependências completas
FROM ruby:3.3-slim AS builder

ARG NODE_VERSION=20

# Definir timezone globalmente
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Variáveis do Rails
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Instale dependências essenciais + certificados
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libvips42 \
      curl \
      git \
      python3 \
      gnupg \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Instale Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x  | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    npm cache clean --force && \
    rm -rf /tmp/npm*

WORKDIR /app

# Copie Gemfile e instale gems
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "$(grep -A1 'BUNDLED WITH' Gemfile.lock | tail -n1 | tr -d ' \r')" && \
    bundle config set path 'vendor/bundle' && \
    bundle config set deployment true && \
    bundle config set without 'development test' && \
    bundle install --retry 3 --jobs $(nproc)

# Pacotes JS
COPY package.json yarn.lock ./
RUN yarn install --check-files --frozen-lockfile

# Código completo
COPY . .
RUN RAILS_ENV=production bundle exec rake assets:precompile

# Limpeza de cache desnecessário
RUN rm -rf tmp/* log/* vendor/bundle/ruby/3.3.0/cache/*.gem

# Etapa Final: Imagem Enxuta
FROM ruby:3.3-slim

ARG NODE_VERSION=20

# Ajuste de timezone e certificados
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Configuração do Rails
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Dependências mínimas para produção
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libpq5 \
      libvips42 \
      ca-certificates \
      nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar apenas artefatos necessários
COPY --from=builder /usr/local/bin/ruby /usr/local/bin/ruby
COPY --from=builder /usr/local/bin/gem /usr/local/bin/gem
COPY --from=builder /usr/local/bin/bundle /usr/local/bin/bundle
COPY --from=builder /usr/local/lib/ruby /usr/local/lib/ruby
COPY --from=builder /app /app

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
