# ================================
# Dockerfile Corrigido para Chatwoot-nestor
# ================================

# ================================
# Stage 1: Builder
# ================================
FROM ruby:3.3.6 AS builder

# Definir variáveis de ambiente
ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/home/rails/app \
    BUNDLE_PATH=/home/rails/bundle \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# Definir diretório de trabalho
WORKDIR ${APP_HOME}

# Instalar dependências do sistema em uma única camada
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      git \
      ca-certificates \
      curl \
      python3 \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Criar usuário não-root
RUN adduser --disabled-password --gecos '' rails && \
    mkdir -p /home/rails/app /home/rails/bundle && \
    chown -R rails:rails /home/rails

# Mudar para usuário não-root
USER rails

# Copiar e instalar dependências Ruby primeiro (melhor cache)
COPY --chown=rails:rails Gemfile Gemfile.lock ./

# Instalar Bundler e configurar
RUN gem install bundler:2.5.16 --no-document && \
    bundle config set --local path "${BUNDLE_PATH}" && \
    bundle config set --local without "${BUNDLE_WITHOUT}" && \
    bundle install --jobs ${BUNDLE_JOBS} --retry ${BUNDLE_RETRY}

# Copiar arquivos de configuração JavaScript primeiro
COPY --chown=rails:rails package.json yarn.lock ./
COPY --chown=rails:rails babel.config.js ./
COPY --chown=rails:rails .babelrc* ./
COPY --chown=rails:rails config/webpack/webpack.config.js config/webpack/
COPY --chown=rails:rails config/webpack/postcss.config.js config/webpack/

# Instalar TODAS as dependências JavaScript (incluindo dev dependencies)
RUN yarn install --frozen-lockfile

# Copiar código fonte completo
COPY --chown=rails:rails . ./

# Verificar se dependências críticas estão instaladas
RUN echo "Verificando dependências críticas..." && \
    ls -la node_modules/@babel/ && \
    ls -la node_modules/babel-loader/ || echo "babel-loader não encontrado" && \
    node -e "console.log('Node.js funcionando:', process.version)" && \
    yarn --version

# Pré-compilar assets com configurações adequadas
RUN NODE_ENV=production \
    RAILS_ENV=production \
    SECRET_KEY_BASE=precompile_placeholder \
    bundle exec rake assets:precompile

# Limpeza pós-build
RUN rm -rf tmp/* log/* node_modules/.cache && \
    yarn cache clean && \
    find ${BUNDLE_PATH} -name "*.c" -delete && \
    find ${BUNDLE_PATH} -name "*.o" -delete

# ================================
# Stage 2: Runtime Final
# ================================
FROM ruby:3.3.6-slim

# Definir variáveis de ambiente para runtime
ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    NODE_ENV=production \
    TZ=UTC \
    APP_HOME=/home/rails/app \
    BUNDLE_PATH=/home/rails/bundle \
    BUNDLE_WITHOUT="development test" \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Definir diretório de trabalho
WORKDIR ${APP_HOME}

# Instalar apenas dependências de runtime necessárias
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      libpq5 \
      ca-certificates \
      curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Criar usuário não-root
RUN adduser --disabled-password --gecos '' rails && \
    mkdir -p /home/rails/app /home/rails/bundle && \
    chown -R rails:rails /home/rails

# Mudar para usuário não-root
USER rails

# Instalar bundler no runtime
RUN gem install bundler:2.5.16 --no-document

# Copiar arquivos essenciais do stage builder
COPY --chown=rails:rails --from=builder ${BUNDLE_PATH} ${BUNDLE_PATH}
COPY --chown=rails:rails --from=builder ${APP_HOME}/public/assets ${APP_HOME}/public/assets
COPY --chown=rails:rails --from=builder ${APP_HOME}/public/packs ${APP_HOME}/public/packs

# Copiar código da aplicação
COPY --chown=rails:rails --from=builder ${APP_HOME}/app ${APP_HOME}/app
COPY --chown=rails:rails --from=builder ${APP_HOME}/bin ${APP_HOME}/bin
COPY --chown=rails:rails --from=builder ${APP_HOME}/config ${APP_HOME}/config
COPY --chown=rails:rails --from=builder ${APP_HOME}/db ${APP_HOME}/db
COPY --chown=rails:rails --from=builder ${APP_HOME}/lib ${APP_HOME}/lib
COPY --chown=rails:rails --from=builder ${APP_HOME}/Gemfile ${APP_HOME}/Gemfile
COPY --chown=rails:rails --from=builder ${APP_HOME}/Gemfile.lock ${APP_HOME}/Gemfile.lock
COPY --chown=rails:rails --from=builder ${APP_HOME}/config.ru ${APP_HOME}/config.ru
COPY --chown=rails:rails --from=builder ${APP_HOME}/Rakefile ${APP_HOME}/Rakefile

# Copiar VERSION se existir
COPY --chown=rails:rails --from=builder ${APP_HOME}/VERSION ${APP_HOME}/VERSION 2>/dev/null || true

# Configurar bundler no runtime
RUN bundle config set --local path "${BUNDLE_PATH}" && \
    bundle config set --local without "${BUNDLE_WITHOUT}"

# Garantir permissões de execução
RUN chmod +x ${APP_HOME}/bin/rails ${APP_HOME}/bin/rake

# Criar diretórios necessários
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log

# Healthcheck para verificar se a aplicação está funcionando
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Expor porta
EXPOSE 3000

# Comando de inicialização
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]


