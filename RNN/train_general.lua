nn = require 'nn'
require 'nngraph'

-- set global variables 
opt = {}

opt.model = 'rnn'
--opt.model = 'lstm'

--opt.dataset = 'toy'
opt.dataset = 'mnist'
--[[ Pixel-by-pixel MNIST, task suggested by Le et al. (2015)
(A simple way to initialize recurrent networks of rectified linear units.)
and reused in Arjovsky et al. (2016) Unitary evolution recurrent
neural networks ]]

path2mnist = '/home/cadene/data/mnist_lecunn/'

batch_size = 20
dim_h = 10
dropout = .5
max_iteration = 1
learning_rate = 0.02
opt.cuda = false

torch.setdefaulttensortype('torch.FloatTensor')

if opt.dataset == 'toy' then
  csv = require 'util/csv'
  toy = require 'util/toy'

  gendata = torch.load('data/toy_gendata.t7')
  data = torch.load('data/toy.t7')
  n = data:size(1)
  len = gendata.len

  x = data:narrow(2, 1, len)
  y = data:narrow(2, len+1, 1)

  pc_train = .7
  n_train = torch.floor(n * pc_train)
  n_test = n - n_train

  x_train = x:narrow(1, 1, n_train)
  y_train = y:narrow(1, 1, n_train)

  x_test = x:narrow(1, n_train+1, n_test)
  y_test = y:narrow(1, n_train+1, n_test)

elseif opt.dataset == 'mnist' then
  mnist = require 'util/mnist'
  tensor_type = torch.getdefaulttensortype()
  len = 28*28 -- 784
  
  trainset = mnist.traindataset(path2mnist)
  n_train = trainset.size -- 60000
  x_train = trainset.data:reshape(n_train,28*28):type(tensor_type)
  y_train = trainset.label:view(n_train,1):type(tensor_type)
  trainset = nil
  
  testset = mnist.testdataset(path2mnist)
  n_test = testset.size -- 10000
  x_test = testset.data:reshape(n_test,28*28):type(tensor_type)
  y_test = testset.label:view(n_test,1):type(tensor_type)
  testset = nil
  
  collectgarbage()  
end
-- normalize trainset and testset
x_train_mean = x_train:mean()
x_train_std = x_train:std()
x_train = (x_train - x_train_mean) / x_train_std
x_test = (x_test - x_train_mean) / x_train_std

-- prepare data structure (trainer)
function create_h0(batch_size, dim_h)
  return torch.zeros(batch_size, dim_h)
end
function create_c0(batch_size, dim_h)
  return torch.zeros(batch_size, dim_h)
end
function create_input(batch_size, dim_h, x)
  local input
  if opt.model == 'mpl' then
    input = x
  elseif opt.model == 'rnn' then
    input = {create_h0(batch_size, dim_h), x}
  elseif opt.model == 'lstm' then
    input = {create_h0(batch_size, dim_h), create_c0(batch_size, dim_h), x}
  end
  if opt.cuda then
    if type(input) == 'table' then
      for i=1,#input do
        input[i] = input[i]:cuda()
      end
    else
      input = input:cuda()
    end
  end
  return input
end

dataset = {}
function dataset:size()
  return torch.floor(n_train / batch_size)
end
for i=1,dataset:size() do
  local start = (i-1)*batch_size + 1
  dataset[i] = {}
  dataset[i][1] = create_input(batch_size, dim_h, x_train:narrow(1, start, batch_size))
  dataset[i][2] = y_train:narrow(1, start, batch_size)
end

if opt.model == 'mlp' then
  mlp = require 'model/mlp'
  model = mlp.create(len, dim_h, 1, dropout)
elseif opt.model == 'rnn' then
  rnn = require 'model/rnn'
  model = rnn.create(len, dim_h)
elseif opt.model == 'lstm' then
  lstm = require 'model/lstm'
  model = lstm.create(len, dim_h, 1)
end

if opt.model == 'rnn' or opt.model == 'lstm' then
  function model:accUpdateGradParameters(input, gradOutput, lr)
    self.gradParameters:zero()
    self:accGradParameters(input, gradOutput, 1)
    self.parameters:add(-lr, self.gradParameters)
  end
end

criterion = nn.MSECriterion()

trainer = nn.StochasticGradient(model, criterion)
trainer.maxIteration = max_iteration
trainer.learningRate = learning_rate
function trainer:hookIteration(iter)
  local input = create_input(n_test, dim_h, x_test)
  print(iter.."# test error = " .. criterion:forward(model:forward(input), y_test))
end

model.parameters:uniform(-0.1, 0.1) -- view article for initialization
model:zeroGradParameters()
print("parameter count: " .. model.parameters:size(1))
print(x_test:size())
input = create_input(n_test, dim_h, x_test)
loss = criterion:forward(model:forward(input), y_test)
print("initial error before training = " .. loss) 
trainer:train(dataset)
input = create_input(n_test, dim_h, x_test)
loss = criterion:forward(model:forward(input), y_test)
print("# testing error = " .. loss)

torch.save('data/'.. opt.model ..'.t7', model)

if opt.dataset == 'toy' then
  -- for displaying
  grid_size = 100
  data_disp = toy.generate_data(grid_size, gendata.max_y, 0.0, gendata.len, gendata.delta, 0)
  x_disp = data_disp:narrow(2, 1, len)
  y_true = data_disp:narrow(2, len+1, 1)
  x_feed = (x_disp - x_train_mean) / x_train_std
  input = create_input(grid_size, dim_h, x_feed)
  y_pred = model:forward(input)
  disp = nn.JoinTable(2):forward{x_disp, y_true, y_pred}
  label = {}
  for i=1,len do
    label[i] = 'x'..i
  end
  label[len+1] = 'y_true'
  label[len+2] = 'y_pred'
  csv.tensor_to_csv(disp, 'data/toy_disp.csv', label)

  print("# display error = " .. y_pred:dot(y_true:t())/grid_size)
end
-- END
