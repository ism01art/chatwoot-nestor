# Etapa de build (com ferramentas de compilação)
FROM ruby:3.3 as builder

ARG NODE_VERSION=18

# Instalar dependências para build
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends build-essential libpq-dev curl gnupg git libvips42 && \
    rm -rf /var/lib/apt/lists/*

# Instalar Node.js e Yarn
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x  | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    npm cache clean --force && \
    rm -rf /tmp/npm*

WORKDIR /app

# Copiar apenas o necessário para instalar dependências
COPY Gemfile Gemfile.lock ./
COPY package.json yarn.lock ./

# Instalar gems e pacotes JS
RUN gem install bundler && bundle config set path 'vendor/bundle' && bundle install --deployment --without development test

RUN yarn install --check-files --frozen-lockfile

# Copiar todo o código
COPY . .

# Compilar assets
RUN RAILS_ENV=production bundle exec rake assets:precompile

# Limpar arquivos desnecessários após build
RUN rm -rf tmp/* log/* vendor/bundle/ruby/3.3.0/cache/*.gem

# Etapa final (imagem enxuta)
FROM ruby:3.3-slim

ARG NODE_VERSION=18

# Dependências mínimas em runtime
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends libpq5 libvips42 ca-certificates nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar gems, app e assets compilados do stage anterior
COPY --from=builder /app /app

# Expondo porta e definindo comando
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
