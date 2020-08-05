when defined(windows):
  include ioselectors/ioselectors_wepoll
else:
  import selectors
  export selectors
