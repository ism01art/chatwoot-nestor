FROM ruby:3.2

ARG NODE_VERSION=18

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev curl gnupg git libvips

RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y nodejs && npm install -g yarn

WORKDIR /app
COPY . .

RUN gem install bundler && bundle install
RUN yarn install --check-files
RUN yarn build && RAILS_ENV=production bundle exec rake assets:precompile

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
