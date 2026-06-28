# Reactor Behavior (aka 'gen_statem')

[![Erlangsters Repository](https://img.shields.io/badge/erlangsters-reactor-%23a90432)](https://github.com/erlangsters/reactor)
![Supported Erlang/OTP Versions](https://img.shields.io/badge/erlang%2Fotp-27%7C28%7C29-%23a90432)
![Current Version](https://img.shields.io/badge/version-0.0.2-%23354052)
![License](https://img.shields.io/github/license/erlangsters/reactor)
[![Build Status](https://img.shields.io/github/actions/workflow/status/erlangsters/reactor/build.yml)](https://github.com/erlangsters/reactor/actions/workflows/build.yml)
[![Documentation Link](https://img.shields.io/badge/documentation-available-yellow)](http://erlangsters.github.io/reactor/)

A re-implementation of the `gen_statem` behavior (from the OTP framework) for
the OTPless distribution of Erlang, named `reactor`.

:construction: It's a work-in-progress, use at your own risk.

Written by the Erlangsters [community](https://about.erlangsters.org/) and
released under the MIT [license](https://opensource.org/license/mit).

## Getting started

To use `reactor` in a `rebar3` project, add it to your `rebar.config`.

```erlang
{deps, [
  {reactor, {git, "https://github.com/erlangsters/reactor.git", {tag, "0.0.2"}}}
]}.
```

XXX: To be written.
