# ================================
# Stage 1: Builder
# ================================
FROM ruby:3.3 AS builder

ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/home/rails/app \
    NPM_CONFIG_PREFIX=/home/rails/.npm-global \
    PATH="/home/rails/.npm-global/bin:${PATH}"

WORKDIR ${APP_HOME}

# Instalar dependências do sistema
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      git \
      ca-certificates \
      nodejs \
      npm \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p ${APP_HOME}

# Adicionar repositório do NodeSource para Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x  | bash - && \
    apt-get install -y nodejs

# Criar usuário não-root antes de qualquer operação
RUN adduser --disabled-password --gecos '' rails || true && \
    mkdir -p /home/rails && \
    chown -R rails:rails /home/rails

USER rails

# Garantir diretórios necessários
RUN mkdir -p ${NPM_CONFIG_PREFIX} ${APP_HOME} ~/.npm

# Copiar Gemfile primeiro
COPY --chown=rails:rails Gemfile Gemfile.lock ./

# Instalar Bundler
ARG BUNDLER_VERSION
RUN gem install bundler:${BUNDLER_VERSION:-2.5.16} --no-document

# Configurar Bundler
RUN bundle config set path 'vendor/bundle' && \
    bundle config set without 'development test'

# Instalar gems
RUN bundle install --jobs $(nproc) --retry 3

# Copiar package.json/yarn.lock
COPY --chown=rails:rails package.json yarn.lock ./

# Instalar Yarn localmente (sem root)
RUN npm install -g yarn --prefix "${NPM_CONFIG_PREFIX}"

# Forçar instalação do Babel e seus presets
RUN yarn add @babel/core @babel/preset-env --dev

# Atualizar browserslist/caniuse-lite (evita erro durante compilação de assets)
RUN npx browserslist@latest --update-db || true

# Instalar dependências JS com force reinstall
RUN rm -rf node_modules package-lock.json yarn.lock build dist && \
    yarn config set cache-folder ./vendor/yarn_cache && \
    yarn install --check-files --force

# Garantir que @babel/preset-env foi instalado
RUN if [ ! -d "node_modules/@babel/preset-env" ]; then echo "❌ Falha crítica: @babel/preset-env não encontrado"; exit 1; fi

# Copiar código fonte completo
COPY --chown=rails:rails . ./

# Pré-compilar assets
ARG SECRET_KEY_BASE
ENV SECRET_KEY_BASE=dummykeyforbuild
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
    APP_HOME=/home/rails/app \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

WORKDIR ${APP_HOME}

# Dependências mínimas no runtime
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libpq5 \
      ca-certificates \
      nodejs \
    && rm -rf /var/lib/apt/lists/*

# Criar usuário não-root
RUN adduser --disabled-password --gecos '' rails || true && \
    mkdir -p ${APP_HOME} && \
    chown -R rails:rails ${APP_HOME}

USER rails

# Copiar apenas arquivos essenciais do stage builder
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
