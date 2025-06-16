# ================================
# Stage 1: Builder
# ================================
FROM ruby:3.3 AS builder

ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/app

WORKDIR ${APP_HOME}

# Instalar dependências de sistema necessárias
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libvips42 \
      git \
      curl \
      ca-certificates \
      nodejs \
      python3 \
      libssl-dev \
      libreadline-dev \
      zlib1g-dev \
      libxml2-dev \
      libxslt1-dev \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p vendor/cache vendor/yarn_cache

# Criar usuário não-root
RUN adduser --disabled-password --gecos '' rails && \
    chown -R rails:rails /app

USER rails

# Copiar Gemfile e Gemfile.lock primeiro para aproveitar o cache do Docker
COPY --chown=rails:rails Gemfile Gemfile.lock ./

# Instalar Bundler na versão compatível com o projeto
ARG BUNDLER_VERSION
RUN gem install bundler:${BUNDLER_VERSION:-2.5.16} --no-document

# Configurar Bundler
RUN bundle config set path 'vendor/bundle' && \
    bundle config set without 'development test'

# Instalar as gems
RUN bundle install --jobs $(nproc) --retry 3 --deployment

# Copiar package.json e yarn.lock antes do código fonte
COPY --chown=rails:rails package.json yarn.lock ./

# Instalar Yarn globalmente e as dependências JS
RUN npm install -g yarn && \
    yarn config set cache-folder ./vendor/yarn_cache && \
    yarn install --frozen-lockfile --check-files

# Copiar todo o código fonte
COPY --chown=rails:rails . .

# Pré-compilar assets
ARG SECRET_KEY_BASE
ENV SECRET_KEY_BASE=${SECRET_KEY_BASE:-dummykeyforbuild}
RUN RAILS_ENV=production bundle exec rake assets:precompile

# Limpeza pós-build
RUN rm -rf tmp/* log/* vendor/cache vendor/yarn_cache doc coverage spec test .yardoc \
    && find /tmp -type f -name '*.gem' -delete \
    && find vendor/bundle -name "*.c" -delete \
    && find vendor/bundle -name "*.o" -delete

# ================================
# Stage 2: Runtime Final
# ================================
FROM ruby:3.3-slim

ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/app \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

WORKDIR ${APP_HOME}

# Dependências mínimas no runtime
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libpq5 \
      libvips42 \
      ca-certificates \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

# Criar usuário não-root
RUN adduser --disabled-password --gecos '' rails && \
    chown -R rails:rails /app

USER rails

# Copiar apenas os arquivos essenciais do stage builder
COPY --chown=rails:rails --from=builder ${APP_HOME}/vendor/bundle ${APP_HOME}/vendor/bundle
COPY --chown=rails:rails --from=builder ${APP_HOME}/public/packs ${APP_HOME}/public/packs
COPY --chown=rails:rails --from=builder ${APP_HOME}/public/assets ${APP_HOME}/public/assets
COPY --chown=rails:rails --from=builder ${APP_HOME}/config ${APP_HOME}/config
COPY --chown=rails:rails --from=builder ${APP_HOME}/bin ${APP_HOME}/bin
COPY --chown=rails:rails --from=builder ${APP_HOME}/db ${APP_HOME}/db
COPY --chown=rails:rails --from=builder ${APP_HOME}/lib ${APP_HOME}/lib
COPY --chown=rails:rails --from=builder ${APP_HOME}/VERSION ${APP_HOME}/VERSION

# Garantir permissão de execução do bin/rails
RUN chmod +x ${APP_HOME}/bin/rails

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
