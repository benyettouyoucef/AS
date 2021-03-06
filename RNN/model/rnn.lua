
local rnn = {}

function rnn.create(dim_x, dim_h, dim_xi)--, dropout, graph2fig)

  local dim_xi = dim_xi or 1
  local h0 = nn.Identity()()
  local x = nn.Identity()()
  local xs = nn.SplitTable(2)(x)
  local h = h0
  for i=1,dim_x do
    local xi
    if dim_xi == 1 then
      xi = nn.Reshape(1)(nn.SelectTable(i)(xs))
    else 
      xi = nn.Reshape(1,dim_xi)(nn.SelectTable(i)(xs)) -- Reshape(1) for batch
    end
    local jt = nn.JoinTable(2,2){h, xi} -- JointTable(2,2) for batch
    h = nn.Tanh()(nn.Linear(dim_h+dim_xi, dim_h)(jt)) -- 1 layer rnn
  end
  local y = nn.Linear(dim_h, dim_xi)(h)
  local model = nn.gModule({h0, x}, {y})

  local table_params, table_gradParams = model:parameters()
  --print(table_params)  
  for t=2,dim_x do
    table_params[2*t-1]:set(table_params[1]) -- share weigths matrix
    table_params[2*t]:set(table_params[2]) -- share biais vector
    table_gradParams[2*t-1]:set(table_gradParams[1]) -- gradient estimate
    table_gradParams[2*t]:set(table_gradParams[2]) -- gradient estimate
  end

  model.parameters, model.gradParameters = model:getParameters()

  return model, model_gen
end

return rnn