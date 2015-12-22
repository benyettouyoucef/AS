nn = require 'nn'
require 'nngraph'
mlp = require 'model/mlp'
csv = require 'util/csv'
toy = require 'util/toy'

-- set global variables 
batch_size = 20
dim_h = 126
dropout = .5
max_iteration = 50
learning_rate = 0.05
cuda = false

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

-- normalize trainset and testset
x_train_mean = x_train:mean()
x_train_std = x_train:std()
x_train = (x_train - x_train_mean) / x_train_std
x_test = (x_test - x_train_mean) / x_train_std

-- prepare data structure (trainer)
dataset = {}
function dataset:size()
  return torch.floor(n_train / batch_size)
end
for i=1,dataset:size() do
  local start = (i-1)*batch_size + 1
  dataset[i] = {}
  dataset[i][1] = x_train:narrow(1, start, batch_size)
  dataset[i][2] = y_train:narrow(1, start, batch_size)
end

model = mlp.create(gendata.len, dim_h, 1, dropout)
parameters, gradParameters = model:getParameters()
criterion = nn.MSECriterion()

trainer = nn.StochasticGradient(model, criterion)
trainer.maxIteration = max_iteration
trainer.learningRate = learning_rate
function trainer:hookIteration(iter)
  print(iter.."# test error = " .. criterion:forward(model:forward(x_test), y_test))
end

parameters:uniform(-0.1, 0.1)
model:zeroGradParameters()
print("parameter count: " .. parameters:size(1))
print(x_test:size())
print("initial error before training = " .. criterion:forward(model:forward(x_test), y_test))
trainer:train(dataset)
print("# testing error = " .. model:forward(x_test):dot(y_test:t())/n_test)

torch.save('data/mlp.t7', model)

-- for displaying
grid_size = 100
data_disp = toy.generate_data(grid_size, gendata.max_y, 0.0, gendata.len, gendata.delta, 0)
x_disp = data_disp:narrow(2, 1, len)
y_true = data_disp:narrow(2, len+1, 1)
x_feed = (x_disp - x_train_mean) / x_train_std
y_pred = model:forward(x_feed)
disp = nn.JoinTable(2):forward{x_disp, y_true, y_pred}
label = {}
for i=1,len do
  label[i] = 'x'..i
end
label[len+1] = 'y_true'
label[len+2] = 'y_pred'
csv.tensor_to_csv(disp, 'data/toy_disp.csv', label)

print("# display error = " .. y_pred:dot(y_true:t())/grid_size)

-- END