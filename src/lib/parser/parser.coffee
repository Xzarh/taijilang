{str, hasOwnProperty, extend, letterCharSet, firstIdentifierCharSet, firstSymbolCharset, taijiIdentifierCharSet, constant, trace} = require '../utils'

{NULL, NUMBER,  STRING,  IDENTIFIER, SYMBOL, REGEXP, PUNCTUATION
PAREN, BRACKET, CURVE,  NEWLINE,  SPACES
LINE_COMMENT, EOI, INDENT, UNDENT, HALF_DENT, SPACE_COMMENT, TAIL_COMMENT
SPACE, RIGHT_DELIMITER, KEYWORD, CONJUNCTION, PREFIX, SUFFIX, BINARY
COMPACT_CLAUSE_EXPRESSION, OPERATOR_EXPRESSION
} = constant

{prefixOperatorDict, binaryOperatorDict} = require './operator'

exports.keywordMap = keywordMap = {'if':1, 'try':1, 'while':1, 'return':1, 'break':1, 'continue':1, 'throw':1,'for':1, 'var':1}
keywordHasOwnProperty = hasOwnProperty.bind(exports.keywordMap)

exports.conjMap = conjMap = {'then':1, 'else':1, 'catch':1, 'finally':1, 'case':1, 'default':1, 'extends':1}
conjunctionHasOwnProperty = hasOwnProperty.bind(exports.conjMap)

begin = (exps) ->
  if not exps then return  'undefined'
  else if exps.length==0 then  'undefined'
  else if exps.length==1 then exps[0]
  else
    result = ['begin!']
    for exp in exps
      if exp[0]=='begin!' then result.push.apply exps[1...]
      else result.push exp
    result

exports.Parser = ->
  parser = @

  # global variable used by lexer
  text = '' # text to be parsed
  textLength = text.length;
  cur = 0 #  the start position pointer of current token while do lexical parsing
  cursor = 0 # the stop position pointer of current token while do lexical parsing
  char = '' # current character, should assure char is the value of text[cursor] whenerver entering or leaving a function
  lineno = 0 # current line number, use line for local line number
  lineStart = 0 # start cursor of current line
  lexIndent = 0 # global lexical indent column of current line, use dent for local indent column
  indent = 0 # global indent while parsing, get from tokens including SPACE, NEWLINE, INDENT, UNDENT, EOI

  # token should have the field:type, value, cursor, cursor, line, column
  # token like SPACE, NEWLINE, INDENT, UNDENT should have the field "indent" which means the indent of the end line of the token
  token = undefined # global token generated by lexical parsing and used by the parser
  tokenType = undefined # global current token.type, set in nextToken(), matchToken or tokenOnXXX
  tokenValue = ''
  cursor2Token = []
  baseCursor = 0

  # global variable used by the syntax parser
  atStatementHead = true # whether is at head of statement

  @cursor = -> cursor
  @endOfInput = -> not text[cursor]

  eoi = {type:EOI, value:'', start:text.length, stop:textLength, column:-1, lexIndent:-1, indent:-1} # line wait to be filled

  # nextToken() can do more things, like set global tokenType, tokenValue, etc, atStatementHead
  @nextToken = nextToken = ->
    if token.indent!=undefined then indent = token.indent
    switch tokenType
      when NEWLINE, INDENT, UNDENT, EOI then atStatementHead = true
    if tkn=tokenFromMemo(cursor) then setToken tkn
    else matchToken()

  # tokenFnMap[char](char) and tokenOnSymbolChar should change the token
  # matchToken() should be called by nextToken()(with the expanded inline form for the performance)
  # ONLY call matchToken() when after know the cursor and char, or changing cursor and char immediately.
  matchToken = ->
    pos = cur = cursor  # cur may be changed while parsing composited token like (), []
    if fn = tokenFnMap[char] then token = fn(char)
    else if not char then eoi.lineno = lineno+1; lineStart = cursor; setToken eoi
    else token = tokenOnSymbolChar()
    memoToken(token, pos)

  @token = -> token

  memoToken = (tkn, pos) -> cursor2Token[pos-baseCursor] = tkn
  tokenFromMemo = (pos) ->  cursor2Token[pos-baseCursor]

  setToken = (tkn) ->
    token = tkn; tokenType = token.type; tokenValue = token.value; cur = token.start; cursor = token.stop; char = text[cursor]
    if tokenType==NEWLINE or tokenType==INDENT or tokenType==UNDENT  then atStatementHead = true;
    token
  skipTokenType = (type) -> if tokenType==type then nextToken()
  skipSPACE = -> (if tokenType==SPACE then nextToken()); token
  nextNonspaceToken = -> nextToken(); skipSPACE(); token
  skipSomeType = (types...) ->
    for t in types then if tokenType==t then nextToken(); return
    return

  rollbackOnType = (type, tkn) -> if tokenType==type then setToken(tkn)

  @tokenFnMap = tokenFnMap = {}

  tokenOnSymbolChar = ->
    while char = text[++cursor]
      if symbolStopChars[char] then break
      # //: line comment,  /!: regexp
      if char=='/' and ((c2=text[cursor+1])=='/' or c2=='!') then break

    {type:tokenType=SYMBOL, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor, line:lineno, column:cur-lineStart}

  symbolStopChars = {}
  for c in ' \t\v\n\r()[]{},;:#\'\".@\\!' then symbolStopChars[c] = true
  for c of firstIdentifierCharSet then symbolStopChars[c] = true
  for c in '0123456789' then symbolStopChars[c] = true

  tokenFnMap[':'] = tokenFnMap['@'] = tokenFnMap['.'] = ->
    first = char; char = text[++cursor]
    while char==first then char = text[++cursor]
    tokenValue = text[cur...cursor]
    if tokenValue==':' then tokenType = PUNCTUATION else tokenType = SYMBOL
    token = {type:tokenType, value:tokenValue, atom:cursor-cur>=2
    start:cur, stop:cursor, line:lineno, column:cur-lineStart}
    if tokenType==SYMBOL then token.atom = true
    return token

  # token started with ' ' and '\t'
  tokenFnMap[' '] = tokenFnMap['\t'] = ->
    line = lineno; indent = lexIndent; char = text[++cursor]
    skipInlineSpace(indent)
    if char
      if char!='\n' and char!='\r'
        {type:tokenType=SPACE, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor,
        line:line, stopLine:lineno, column:cur-lineStart, indent:lexIndent}
      else
        newLineAndEmptyLines()
        {type:tokenType, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor, line:line, column:cur-lineStart, indent:lexIndent}
    else {type:tokenType=EOI, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor, line:line, column:cur-lineStart, indent:-1}

  # skipInlineSpace is called by tokenOnSpaceChar
  # skiptInlineSpace should not generate independent token and called independently
  skipInlineSpace = ->
    while char==' ' or char=='\t' then char = text[++cursor]
    if char=='/' and text[cursor+1]=='/'
      # don't need to process column here, because want to skip characters until reaching new line
      cursor += 2; char = text[cursor]
      while char!='\n' and char!='\r' then char = text[++cursor]

  # \n\r, \r\n, \r, \n, don't eat spaces.
  newline = ->
    if (c=char)=='\r'
      cursor++;
      if (c2=text[cursor])=='\n' then cursor++; c2 = '\n'
      char = text[cursor]; lineno++; lineStart = cursor
    else if char=='\n'
      cursor++
      if (c2=text[cursor])=='\r' then cursor++; c2 = '\r'
      char = text[cursor]; lineno++; lineStart = cursor
    else return
    c+(c2 or '')

  tokenOnNumberChar = ->
    base = 10
    if char=='0' and c2 = text[cursor+1]
      if c2=='x' or c2=='X' then base = 16; baseStart = cursor += 2; char = text[cursor]
      else char = text[++cursor]; meetDigit = true; baseStart = cursor
    else meetDigit = true; baseStart = cursor
    if base==16
      while char
        if  not('0'<=char<='9' or 'a'<=char<='f' or 'A'<=char<='F') then break
        else char = text[++cursor]
    if base==16
      if char=='.' then lexError 'hexadecimal number followed by "."'
      else if letterCharSet[char] then lexError 'hexadecimal number followed by g-z or G-Z'
      if cursor==baseStart then cursor--; char = text[cursor]
      return {type:tokenType=NUMBER, value:(tokenValue=text[cur...cursor]), atom:true
      start:cur, stop:cursor, line:lineno, column:cur-lineStart}
    # base==10
    while char
      if '0'<=char<='9' then meetDigit = true; char = text[++cursor]
      else break
    # if not meetDigit then return symbol # comment because in no matchToken solution
    if not meetDigit then return
    if char=='.'
      meetDigit = false
      char = text[++cursor]
      while char
        if char<'0' or '9'<char then break
        else meetDigit = true; char = text[++cursor]
    dotCursor = cursor-1
    if not meetDigit and char!='e' and char!='E'
      cursor = dotCursor; char = text[cursor]
    else if char=='e' or char=='E'
      char = text[++cursor]
      if char=='+' or char=='-'
        char = text[++cursor]
        if not char or char<'0' or '9'<char
          cursor = dotCursor; char = text[cursor]
        else
          while char
            char = text[++cursor]
            if  char<'0' or '9'<char then break
      else if not char or char<'0' or '9'<char
        cursor = dotCursor; char = text[cursor]
      else while char
          if  char<'0' or '9'<char then break
          char = text[++cursor]
    {type:tokenType=NUMBER, value:(tokenValue=text[cur...cursor]), atom:true
    start:cur, stop:cursor, line:lineno, column:cur-lineStart}

  isNewlineChar = (c) -> c== '\n' or c=='\r'

  leftRegexp = ->
    while char
      if char=='\\'
        if (c2=text[cursor+1]=='/') or c2=='\\' then cursor += 2; char = text[cursor]
        else char = text[cursor++]
      else if isNewlineChar(char)
        parseError 'meet unexpected new line while parsing regular expression'
      else if char=='/'
        i = 0; char = text[++cursor]
        # console.log text.slice(cursor)
        while char
          if char=='i' or char=='g'or char=='m' then char = text[++cursor]; ++i
          else break
          if i>3 then parseError 'too many modifiers "igm" after regexp'
        return
      else char = text[++cursor]
    if not char then parseError 'unexpected end of input while parsing regexp'

  # back slash \ can be used to escape keyword, conjunction, symbol
  tokenFnMap['\\'] = tokenOnBackSlashChar = ->
    char = text[++cursor]; line = lineno
    if firstIdentifierCharSet[char]
      tkn = tokenOnIdentifierChar()
      tkn.type = tokenType = IDENTIFIER
      tkn.escaped = true; tkn.start = cur; tkn.atom = true
      return tkn
    else if firstSymbolCharset[char]
      tkn = tokenOnSymbolChar()
      tkn.escaped = true; tkn.start = cur; token.value = tokenValue = '\\'+tokenValue
      return tkn
    else if char==':'
      tkn = tokenOnColonChar()
      tkn.value = tokenValue = '\\'+tokenValue; token.type = tokenType = SYMBOL
      tkn.escaped = true; tkn.start = cur
      return tkn
    else if char=="'"
      tkn = tokenOnQuoteChar()
      if text[cur+2]=="'" and text[cur+3]=="'"
        # do not escape '''...'''
        char = text[++cursor]
        return {type:tokenType=SYMBOL, value:(tokenValue='\\'), start:cur, stop:cursor
        line:lineno, column:cur-lineStart, indent:lexIndent}
      else
        for c in text[cur+2...tkn.cursor]
          if c=='\n' or c=='\r' then parseError 'unexpected new line characters in escaped string'
        tkn.escaped = true; tkn.start = cur; tkn.atom = true
        return tkn
    else
      while char=text[++cursor]=='\\' then true
      return {type:tokenType=SYMBOL, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor
      line:lineno, column:cur-lineStart}

  tokenFnMap['/'] = ->
    char = text[++cursor]; line = lineno; indent = lexIndent
    # // start a line comment
    if char=='/' # // leading line comment
      # skip line tail
      cursor++; char=text[cursor]
      while char and char!='\n' and char!='\r' then cursor++; char=text[cursor]
      if char
        if char!='\n' and char!='\r'
          {type:tokenType=SPACE, value:(tokenValue=text[cur...cursor]), start:cur, stop:cursor, line:line, stopLine:lineno, column:cur-lineStart, indent:lexIndent}
        else
          newLineAndEmptyLines()
          {type:tokenType, value:(tokenValue= text[cur...cursor]), start:cur, stop:cursor, line:line, column:cur-lineStart, indent:lexIndent}
      else {type:tokenType=EOI, value:(tokenValue= text[cur...cursor]), start:cur, stop:cursor, line:line, column:cur-lineStart, indent:lexIndent}
    # /! start a regexp
    else if char=='!'
      cursor += 2; char = text[cursor]; leftRegexp()
      {type:tokenType=REGEXP, value:(tokenValue=['regexp!', '/'+text[cur+2...cursor]]), atom:true, start:cur, stop:cursor, line:lineno, column:cur-lineStart}
    else char = text[--cursor];  tokenOnSymbolChar()

  newLineAndEmptyLines = ->
    while newline()
      while char and char==' ' then char = text[++cursor]
      if char=='\t' then parseError 'unexpected tab character "\t" at the head of line'
      if not char or (char!='\n' and char!='\r') then break
    if not char then tokenType = EOI; lexIndent = -1
    else
      lexIndent = cursor-lineStart
      if lexIndent>indent then tokenType = INDENT
      else if lexIndent<indent then tokenType = UNDENT
      else tokenType = NEWLINE

  # the token leaded by '\n', '\r', maybe return token with type NEWLINE, INDENT, UNDENT, EOI
  tokenFnMap['\n'] = tokenFnMap['\r'] = tokenOnNewlineChar = ->
    line = lineno; indent = lexIndent
    newLineAndEmptyLines()
    return {type:tokenType, value:(tokenValue=text[cur...cursor]),
    start:cur, stop:cursor,
    line:line, column:cur-lineStart, indent:lexIndent}

  identifierCharSet = taijiIdentifierCharSet

  tokenOnIdentifierChar = ->
    char = text[++cursor]
    while char and identifierCharSet[char] then char=text[++cursor]
    if char=='=' and text[cursor-1]=='!' then char = text[--cursor]
    txt = text[cur...cursor]
    if keywordHasOwnProperty(txt) then tokenType = KEYWORD; isAtom = false
    else if conjunctionHasOwnProperty(txt) then tokenType = CONJUNCTION; isAtom = false
    else tokenType = IDENTIFIER; isAtom = true
    {type:tokenType, value:(tokenValue=txt), atom:isAtom
    start:cur, stop:cursor,
    line:lineno, column:cur-lineStart}

  for c of firstIdentifierCharSet then tokenFnMap[c] = tokenOnIdentifierChar

  for c in '0123456789' then tokenFnMap[c] = tokenOnNumberChar

  tokenFnMap[','] = tokenFnMap[';'] = ->
    char = text[++cursor]
    {type:tokenType=PUNCTUATION, value:(tokenValue=','), line:lineno, start:cursor, stop:cursor, column:cur-lineStart}

  tokenFnMap["'"] = tokenFnMap['"'] = tokenOnQuoteChar = ->
    quote = char; char = text[++cursor]
    while char
      if char==quote
        char = text[++cursor]
        return {type:tokenType=STRING, value:(tokenValue=text[cur...cursor]), atom:true, start:cur, stop:cursor, line:lineno, column:cur-lineStart}
      else if char=='\\'
        char = text[++cursor]
        if isNewlineChar(char) then parseError 'unexpected new line while parsing string'
        char = text[++cursor]
      else if isNewlineChar(char) then parseError 'unexpected new line while parsing string'
      else char = text[++cursor]
    parseError "expect "+quote+", unexpected end of input while parsing interpolated string"

  tokenFnMap['('] = ->
    line = lineno; char = text[++cursor]
    nextToken()
    if tokenType==UNDENT then parseError 'unexpected undent while parsing parenethis "(...)"'
    ind = indent = lexIndent
    if tokenType==SPACE or tokenType==NEWLINE or tokenType==INDENT then nextToken()
    if tokenValue==')' then exp = ['()']
    else
      exp = parser.operatorExpression()
      if tokenType==UNDENT
        if token.indent<ind then parseError 'expect ) indent equal to or more than ('
        else nextToken()
      else skipSPACE(); if tokenValue!=')' then parseError 'expect )'
      exp = ['()', exp]
    return extend exp, {type:tokenType=PAREN, start:cur, stop:cursor
    line:line, column:cur-lineStart, indent:lexIndent, atom:true, parameters:true}

  tokenFnMap['['] = tokenOnLeftBracketChar = ->
    trace "tokenFnMap['[']: ",  nextPiece()
    char = text[++cursor]; line = lineno; nextToken()
    exp = parser.block() or parser.lineBlock()
    if tokenType==UNDENT
      if token.indent<ind then parseError 'unexpected undent while parsing parenethis "[...]"'
      else nextToken()
    if tokenValue!=']' then parseError 'expect ]'
    nextToken()
    if not exp then value = ['[]']
    else value = [('[]'), exp]
    return memoToken extend value, {type:tokenType=BRACKET, start:cur, stop:cursor
    line:line, column:cur-lineStart, indent:lexIndent, atom:true}

  tokenFnMap['{'] = ->
    trace "tokenFnMap['{']: " +nextPiece()
    char = text[++cursor]; line = lineno; ind = lexIndent
    nextToken()
    skipSPACE()
    if tokenValue=='}' and tkn=nextToken()
      return extend ['{}'],  {atom:true, start:cur, stop:cursor
      line:line, column:column, indent:lexIndent}
    body = parser.block() or parser.lineBlock()
    if tokenType==UNDENT and token.indent<ind then nextToken()
    if tokenValue!='}' then parseError 'expect }'
    tkn = nextToken()
    # To make interpolated string happy, we can not call nextToken() here
    if indent<ind then parseError 'unexpected undent while parsing parenethis "{...}"'
    extend ['{}', begin(body)], {
    type:tokenType=CURVE, atom:true, start:cur, stop:cursor
    line:line, column:cur-lineStart, indent:lexIndent}

  tokenOnRightDelimiterChar = ->
    c = char; char = text[++cursor]
    {type:tokenType=RIGHT_DELIMITER, value:(tokenValue=c), start:cur, stop:cursor,
    line:lineno, column:cur-lineStart}

  for c in ')]}' then tokenFnMap[c] = tokenOnRightDelimiterChar

  @prefixOperator = (mode) ->
    tokenText = tokenValue
    if not hasOwnProperty.call(prefixOperatorDict, tokenText) then return
    op = prefixOperatorDict[tokenText]
    if op.definition and mode==COMPACT_CLAUSE_EXPRESSION then return
    opToken = token; nextToken()
    if mode==COMPACT_CLAUSE_EXPRESSION
      if tokenType==SPACE or tokenType==INDENT or tokenType==NEWLINE or tokenType==UNDENT then setToken(opToken); return
    else
      skipSPACE()
      if tokenType==RIGHT_DELIMITER then error 'unexpected '+tokenValue
      else if tokenType==EOI then error 'unexpected end of input'
      else if tokenType==INDENT or tokenType==NEWLINE or tokenType==UNDENT then nextToken()
    {value:opToken.value, priority:op.priority}

  @binaryOperator = (mode, dent) ->
    start = token
    switch tokenType
      when PAREN then return  {value:'concat()', priority:200, start:token}
      when BRACKET then return {value:'concat[]', priority:200, start:token}
    if tokenType==SPACE
      if mode== COMPACT_CLAUSE_EXPRESSION then return
      else
        nextToken()
        if tokenType==INDENT or tokenType==NEWLINE then nextToken()
    switch tokenType
      when INDENT then (if mode== COMPACT_CLAUSE_EXPRESSION then return else nextToken())
      when NEWLINE then (if mode== COMPACT_CLAUSE_EXPRESSION then return else nextToken())
      when UNDENT
        if mode== COMPACT_CLAUSE_EXPRESSION then return
        else if indent<dent then parseError 'wrong indent' else nextToken()
      when PUNCTUATION
        if mode== COMPACT_CLAUSE_EXPRESSION then return
        else if tokenValue==',' then nextNonspaceToken(); return {value:',', priority:5}
        else return
    if tokenType!=IDENTIFIER and tokenType!=SYMBOL then return
    if not hasOwnProperty.call(binaryOperatorDict, tokenValue) then setToken(start);  return
    op = binaryOperatorDict[opValue=tokenValue]
    nextToken()
    if mode!= COMPACT_CLAUSE_EXPRESSION then skipSPACE(); skipSomeType(NEWLINE, INDENT, UNDENT)
    else if tokenType==NEWLINE or tokenType==INDENT or tokenType==UNDENT or tokenType==EOI then setToken(start); return
    {value:opValue, priority:op.priority, rightAssoc:op.rightAssoc, assign:op.assign}

  @prefixExpression = (mode, priority) ->
    # current global prority doesn't affect prefixOperator
    start = token
    if op=parser.prefixOperator(mode)
      pri = if priority>op.priority then priority else op.priority
      x = parser.expression(mode, pri, true)
      if x
        return extend ['prefix!', op.value, x], {
        expressionType:PREFIX, priority:op.priority, rightAssoc:op.rightAssoc}
      else setToken(start); return

  @expression = expression = (mode, priority, leftAssoc) ->
    if not x = parser.prefixExpression(mode, priority)
      if not token.atom then return
      else x = token; x.priority = 1000; nextToken()
    while tkn2 = token
      if (op=parser.binaryOperator(mode, x))
        if (opPri=op.priority)>priority  or (opPri==priority and not leftAssoc)
          # should assure that a right operand is here while parsing binary operator
          if y = expression(mode, opPri, not op.rightAssoc)
            x = extend ['binary!', op.value, x, y], {
            expressionType:BINARY, priority:op.priority, rightAssoc:op.rightAssoc}
            continue
        setToken(tkn2);  break
      else break
    x

  @operatorExpression = -> parser.expression(OPERATOR_EXPRESSION, 0, true)
  @compactClauseExpression = -> parser.expression(COMPACT_CLAUSE_EXPRESSION, 0, true)

  expectThen = (isHeadStatement, clauseIndent) ->
    skipSPACE()
    if atStatementHead and not isHeadStatement then parseError 'unexpected new line before "then" of inline keyword statement'
    if tokenType==INDENT then parseError 'unexpected indent before "then"'
    else if tokenType==EOI
      parseError 'unexpected end of input, expect "then"'
    if tokenType==NEWLINE then nextToken()
    else if tokenType==UNDENT and token.indent>=clauseIndent then nextToken()
    if atStatementHead and indent!=clauseIndent then parseError 'wrong indent before "then"'
    if tokenType==CONJUNCTION
      if tokenValue=="then" then nextToken(); return true
      else parseError 'unexpected conjunction "'+tokenValue+'", expect "then"'
    else parseError 'expect "then"'

  maybeConjunction = (conj, isHeadStatement, clauseIndent) ->
    if atStatementHead and not isHeadStatement then return
    if tokenType==EOI then return
    if indent<clauseIndent then return
    if indent>clauseIndent then parseError 'wrong indent'
    if indent==clauseIndent and tokenType==CONJUNCTION and tokenValue==conj
      conj = token; nextToken(); return conj

  # if test then action else action
  keywordThenElseStatement = (keyword) -> (isHeadStatement) ->
    ind = indent; nextNonspaceToken()
    if not (test=parser.clause()) then parseError 'expect a clause after "'+keyword+'"'
    expectThen(isHeadStatement, ind)
    then_ = parser.block() or parser.line()
    if tokenType==NEWLINE then tkn = token; nextToken()
    if maybeConjunction('else', isHeadStatement, ind)
      else_ = parser.block() or parser.line()
    else if tkn then token = tkn; tokenType = token.type
    if else_ then [keyword, test, begin(then_), begin(else_)]
    else [keyword, test, begin(then_)]

  # throw or return value
  throwReturnStatement = (keyword) -> (isHeadStatement) ->
    nextNonspaceToken()
    if clause = parser.clause() then [keyword, clause]
    else [keyword]

  # break; continue
  breakContinueStatement = (keyword) -> (isHeadStatement) ->
    nextNonspaceToken()
    if tokenType==IDENTIFIER
      label = token; nextNonspaceToken()
      [keyword, label]
    else skipSPACE(); [keyword]

  @keyword2statement = keyword2statement =

    'break': breakContinueStatement('break')
    'continue': breakContinueStatement('continue')
    'throw': throwReturnStatement('throw')
    'return': throwReturnStatement('return')
    'new': throwReturnStatement('new')

    'if': keywordThenElseStatement('if')
    'while': keywordThenElseStatement('while')

    'for': (isHeadStatement) ->
      ind = indent; nextToken()
      skipSPACE()
      if tokenType!=IDENTIFIER then parseError 'expect identifier'
      name1 = token
      nextToken()
      skipSPACE()
      if tokenValue==',' # optional ","
        nextNonspaceToken()
      if tokenType!=IDENTIFIER then parseError 'expect "in", "of" or index variable name'
      if tokenValue=='in' or tokenValue=='of' then inOf = value; nextToken()
      else
        name2 = token; nextNonspaceToken()
        if tokenValue=='in' or tokenValue=='of' then inOf = value; nextToken()
        else  'expect "in" or "of"'
      skipSPACE()
      obj = parser.clause()
      expectThen(isHeadStatement, ind)
      body = parser.block() or parser.line()
      if inOf=='in' then kw = 'forIn!' else kw = 'forOf!'
      [kw, name1, name2, obj, begin(body)]

    'try': (isHeadStatement) ->
      ind = indent; nextToken(); # skip "try"
      skipSPACE()
      if not (test = parser.block() or parser.line()) then parseError 'expect a line or block after "try"'
      if atStatementHead and not isHeadStatement
        parseError 'meet unexpected new line when parsing inline try statement'
      if maybeConjunction("catch", isHeadStatement, ind)
        skipSPACE(); atStatementHead = false
        if tokenType==IDENTIFIER
          catchVar = token; nextToken()
        skipSPACE()
        if tokenType!=CONJUNCTION or tokenValue!='then'
          parseError('expect "then" after "catch +'+catchVar.value+'"')
        nextNonspaceToken()
        catch_ = parser.block() or parser.line()
      if maybeConjunction("finally", isHeadStatement, ind)
        skipSPACE()
        final = parser.block() or parser.line()
        ['try', test, catchVar, begin(catch_)]
      else ['try', begin(test), catchVar, begin(catch_), begin(final)]

  @sequence = ->
    clause = []
    while 1
      skipSPACE(); tkn = token
      if (item=parser.compactClauseExpression())
        if item=='#' then setToken(tkn); break # meta call [caller # args...]
        else clause.push item
      else break
    if not clause.length then return
    clause

  makeClause = (items) -> if items.length==1 then items[0] else items

  leadWordClauseMap = {}

  # preprocess opertator #, see metaConvertFnMap['#'] and preprocessMetaConvertFnMap for more information
  # evaluate in compile time ##, see metaConvertFnMap['##']
  # evaluate in both compile time and run time #/, see metaConvertFnMap['#/']
  # escape from compile time to runtime #-, see metaConvertFnMap['#-']
  # #&: metaConvert exp and get the current expression(not metaConverted raw program), see metaConvertFnMap['#&']

  for sym in ['~', '`', '^', '^&', '#', '##', '#/', '#-', '#&'] then leadWordClauseMap[sym] = (tkn, clause) ->  [tkn, clause]

  leadTokenClause = (fn) -> ->
    start = token
    if (type=nextToken().type)!=SPACE and type!=INDENT then setToken(start);  return
    nextToken()
    if not (fn=leadWordClauseMap[start.value]) then setToken(start);  return
    fn(start, parser.clause())

  symbol2clause = {}
  for key, fn of leadWordClauseMap then symbol2clause[key] = leadTokenClause(fn)

  @definitionSymbolBody = definitionSymbolBody = ->
    start = token; nextNonspaceToken()
    if tokenType==INDENT then body = parser.block()
    else body = parser.line()
    [start, [], begin(body)]

  symbol2clause['->'] = symbol2clause['=>'] = definitionSymbolBody

  nextPiece = ->
    if not char then 'end of input'
    else text[cursor...(cursor+8>textLength? textLength: cursor+8)]

  @clause = ->
    trace("clause: "+nextPiece())
    skipSPACE()
    switch tokenType
      when KEYWORD
        isStatementHead = atStatementHead
        atStatementHead = false
        return keyword2statement[tokenValue](isStatementHead)
      when SYMBOL
        if (fn=symbol2clause[tokenValue]) and (result = fn()) then return result
      when PUNCTUATION then error 'unexpected '+tokenValue
      when NEWLINE, UNDENT, RIGHT_DELIMITER, CONJUNCTION, EOI then return

    items = parser.sequence()

    if (op=binaryOperatorDict[tokenValue]) and op.definition
      definition = definitionSymbolBody()
      if not items then return definition
      last = items[(itemsLength=items.length)-1].parameters
      if last.parameter
        definition[1] = last
        if itemsLength==1 then return definition
        items[clauseLength-1] = defintion
        return makeClause(items)

    if tokenValue==',' then nextToken(); return makeClause(items)

    else if tokenValue==':'
      nextToken()
      if tokenType==INDENT then clauses = parser.block()
      else clauses = parser.clauses()
      if clauses.length==0 then parseError 'expected arguments list after ":"'
      clauses.unshift makeClause(items)
      clauses

    else if tokenValue=='#' and nextToken()
      if tokenType==INDENT then clauses = parser.block(); return ['#', makeClause(items), clauses]
      else clauses = parser.clauses(); return ['#', makeClause(items), clauses]

    else if tokenType==INDENT
      tkn = token; nextToken()
      if tokenType==CONJUNCTION then setToken(tkn); return items
      else
        setToken(tkn); blk = parser.block()
        items.push.apply items, blk
        return items

    else makeClause(items)

  @clauses = ->
    result = []; tkn = token
    while clause=parser.clause()
      result.push clause
      if tkn==token then parseError 'oops! inifinte loops!!!'
      tkn = token;
    return result

  @sentence = ->
    if tokenType==EOI or tokenType==INDENT or tokenType==UNDENT or tokenType==NEWLINE or tokenType==RIGHT_DELIMITER or tokenType==CONJUNCTION then return
    result = parser.clauses()
    if tokenValue==';' and nextToken() then skipTokenType SPACE
    result

  @line = ->
    if tokenType==UNDENT or tokenType==RIGHT_DELIMITER or tokenType==CONJUNCTION or tokenType==EOI then return
    if tokenType==INDENT then return parser.block(indent)
    result = []; tkn = token
    while x=parser.sentence()
      result.push.apply result, x
      if tkn==token then parseError 'oops! inifinte loops!!!'
      tkn = token
    result

  @block = -> skipTokenType INDENT; return parser.blockWithoutIndentHead(indent)

  # a block with out indent( the indent has been ate before).
  # stop until meet a undent (less indent than the intent of the start line)
  @blockWithoutIndentHead = (dent) ->
    result = []; ind = indent
    while (x=parser.line())
      result.push.apply result, x
      if tokenType==NEWLINE then nextToken(); continue
      if tokenType==EOI then break
      else if tokenType==UNDENT
        if indent<dent then break
        else if indent==dent then nextToken(); break
        else if indent==ind then nextToken(); continue
        else parseError 'wrong indent'
      else if tokenType==CONJUNCTION then parseError 'unexpected conjunction "'+tokenValue+'" following a indent block'
    return result

  @lineBlock = (dent) ->
    result = parser.line()
    skipSomeType(NEWLINE, SPACE); tkn = token
    skipTokenType(INDENT); rollbackOnType(CONJUNCTION, tkn)
    if tokenType==CONJUNCTION then setToken(tkn)
    else
      setToken(tkn)
      if token.indent>dent then result.push.apply result, parser.blockWithoutIndentHead()
    result

  @module = ->
    nextToken(); body = []
    while x=parser.line()
      skipTokenType NEWLINE; body.push.apply body, x;
      cursor2Token = []; baseCursor = cursor
    if tokenType!=EOI then parseError 'expect end of input, but meet "'+text.slice(cursor)+'"'
    begin(body)

  @init = (data, cur) ->
    text = data; textLength = text.length
    cursor = cur; char = text[cursor]; lineno = 1; lineStart = 0
    token = {type:tokenType=NULL, value:tokenValue='', start:0, stop:0, line:lineno, column:1} # a fake token, because nextToken will use token.indent
    cursor2Token = []; baseCursor = 0
    atStatementHead = true

  @parse = (data, root, cur) -> parser.init(data, cur); root()

  parseError = (message, tkn) ->
    tkn = tkn or token; pos = token.start
    throw pos+'('+tkn.line+':'+tkn.column+'): '+message+': '+text[tkn.start...tkn.stop]

  return
