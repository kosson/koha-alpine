#!/bin/sh

set -eu

KOHA_SOURCE_DIR="${1:?Usage: install-koha-perl-dependencies.sh KOHA_SOURCE_DIR}"
cd "${KOHA_SOURCE_DIR}"

cpanm --notest --local-lib=/opt/koha-perl --installdeps .
cpanm --notest --local-lib=/opt/koha-perl \
    Mojolicious::Plugin::OpenAPI Mojolicious::Plugin::OAuth2 Mojolicious::Plugin::OAuth2::Server \
    Mojolicious::Plugin::AssetPack Mojo::JWT Net::OAuth2::AuthorizationServer Crypt::JWT Struct::Diff \
    PDF::API2 PDF::Reuse GD::Barcode::QRcode Barcode::Code128 Net::Z3950::ZOOM \
    MARC::Record MARC::File::XML MARC::Charset Search::Elasticsearch CHI CHI::Driver::Memcached \
    Cache::Memcached::Fast Gravatar::URL Locale::PO Business::ISBN Business::ISMN Business::ISSN \
    Algorithm::CheckDigits Authen::CAS::Client Crypt::Eksblowfish Crypt::OpenSSL::RSA Crypt::OpenSSL::Random \
    Email::Stuffer Email::Valid Email::MIME Email::Sender Email::Address::XS Template::Plugin::JSON::Escape \
    HTML::Template::Pro HTML::Scrubber DateTime::Format::MySQL DateTime::Format::ISO8601 \
    DateTime::Format::DateParse DateTime::Format::Mail DateTime::Format::W3CDTF \
    Plack::Middleware::ReverseProxy WWW::CSRF HTTP::OAI HTTP::BrowserDetect Net::Stomp OAuth::Lite \
    String::Random Number::Phone Sereal Data::Pagination File::MimeInfo::Magic XML::Writer
