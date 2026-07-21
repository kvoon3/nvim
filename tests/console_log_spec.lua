local console_log = require 'config.console-log'

describe('console snippets', function()
  it('labels expressions', function()
    assert.are.equal("console.log('user.name', user.name)", console_log.format('log', 'user.name'))
  end)

  it('prints simple string literals without a duplicate label', function()
    assert.are.equal("console.warn('it\\'s ready')", console_log.format('warn', '"it\'s ready"'))
  end)

  it('preserves template literals and escaped strings as expressions', function()
    assert.are.equal("console.log('`hello ${name}`', `hello ${name}`)", console_log.format('log', '`hello ${name}`'))
    assert.are.equal([[console.log('\'it\\\'s\'', 'it\'s')]], console_log.format('log', [['it\'s']]))
  end)

  it('uses console.table data as its first argument', function()
    assert.are.equal('console.table(users)', console_log.format('table', 'users'))
  end)
end)
