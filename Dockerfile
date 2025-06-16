# ================================
# Stage 1: Builder
# ================================
FROM ruby:3.3 AS builder

ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/home/rails/app

WORKDIR ${APP_HOME}

# Dependências de sistema
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      curl \
      git \
      gnupg \
      libvips42 \
      ca-certificates \
      nodejs \
      python3 \
      libssl-dev \
      libreadline-dev \
      zlib1g-dev \
      libxml2-dev \
      libxslt1-dev \
      && rm -rf /var/lib/apt/lists/*

# Usuário não-root
RUN adduser --disabled-password --gecos '' rails && \
    mkdir -p /home/rails/app && \
    chown -R rails:rails /home/rails/app

USER rails

# Copiar Gemfile, Gemfile.lock, package.json, yarn.lock
COPY --chown=rails:rails Gemfile Gemfile.lock ./
COPY --chown=rails:rails package.json yarn.lock ./

# Bundler específico (com fallback para a versão mais comum)
ARG BUNDLER_VERSION
RUN gem install bundler:${BUNDLER_VERSION:-2.5.16} --no-document && \
    bundle config set path 'vendor/bundle' && \
    bundle config set without 'development test'

# Instalar gems e dependências Ruby
RUN bundle install --jobs $(nproc)

# Instalar dependências JS
RUN yarn install --frozen-lockfile --check-files

# Copiar código fonte completo
COPY --chown=rails:rails . .

# Pré-compilar assets (SECRET_KEY_BASE é exigido pelo Rails, dummykey garante o build)
ARG SECRET_KEY_BASE
ENV SECRET_KEY_BASE=${SECRET_KEY_BASE:-dummykeyforbuild}
RUN RAILS_ENV=production bundle exec rake assets:precompile

# Limpeza pós-build
RUN rm -rf tmp/* log/* vendor/cache vendor/yarn_cache vendor/assets/bower_components \
    vendor/bundle/.cache vendor/bundle/rdoc doc coverage spec test .yardoc \
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
    APP_HOME=/home/rails/app \
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

RUN adduser --disabled-password --gecos '' rails && \
    mkdir -p ${APP_HOME} && \
    chown -R rails:rails ${APP_HOME}

USER rails

# Copiar apenas o necessário do builder (incluindo public/assets se existir)
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
