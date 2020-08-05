when defined(windows):
  import ioselectors/ioselectors_wepoll
  export ioselectors_wepoll
else:
  import selectors
  export selectors
