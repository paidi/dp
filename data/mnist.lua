------------------------------------------------------------------------
--[[ Mnist ]]--
-- http://yann.lecun.com/exdb/mnist/
-- A simple but widely used handwritten digits classification problem.
------------------------------------------------------------------------
local Mnist, DataSource = torch.class("dp.Mnist", "dp.DataSource")
Mnist.isMnist = true

Mnist._name = 'mnist'
Mnist._image_size = {28, 28, 1}
Mnist._image_axes = 'bhwc'
Mnist._feature_size = 1*28*28
Mnist._classes = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}

function Mnist:__init(config) 
   config = config or {}
   assert(torch.type(config) == 'table' and not config[1], 
      "Constructor requires key-value arguments")
   local args, load_all, input_preprocess, target_preprocess
   args, self._valid_ratio, self._train_file, self._test_file, 
         self._data_path, self._scale, self._binarize, self._shuffle,
         self._download_url, load_all, input_preprocess, 
         target_preprocess
      = xlua.unpack(
      {config},
      'Mnist', nil,
      {arg='valid_ratio', type='number', default=1/6,
       help='proportion of training set to use for cross-validation.'},
      {arg='train_file', type='string', default='mnist-th7/train.th7',
       help='name of training file'},
      {arg='test_file', type='string', default='mnist-th7/test.th7',
       help='name of test file'},
      {arg='data_path', type='string', default=dp.DATA_DIR,
       help='path to data repository'},
      {arg='scale', type='table', 
       help='bounds to scale the values between. [Default={0,1}]'},
      {arg='binarize', type='boolean', 
       help='binarize the inputs (0s and 1s)', default=false},
      {arg='shuffle', type='boolean', 
       help='shuffle different sets', default=true},
      {arg='download_url', type='string',
       default='http://data.neuflow.org/data/mnist-th7.tgz',
       help='URL from which to download dataset if not found on disk.'},
      {arg='load_all', type='boolean', 
       help='Load all datasets : train, valid, test.', default=true},
      {arg='input_preprocess', type='table | dp.Preprocess',
       help='to be performed on set inputs, measuring statistics ' ..
       '(fitting) on the train_set only, and reusing these to ' ..
       'preprocess the valid_set and test_set.'},
      {arg='target_preprocess', type='table | dp.Preprocess',
       help='to be performed on set targets, measuring statistics ' ..
       '(fitting) on the train_set only, and reusing these to ' ..
       'preprocess the valid_set and test_set.'}  
   )
   self._scale = self._scale or {0,1}
   if load_all then
      self:loadTrain()
      self:loadValid()
      self:loadTest()
   end
   DataSource.__init(self, {train_set=self:trainSet(), 
                            valid_set=self:validSet(),
                            test_set=self:testSet(),
                            input_preprocess=input_preprocess,
                            target_preprocess=target_preprocess})
end


function Mnist:loadTrain()
   --Data will contain a tensor where each row is an example, and where
   --the last column contains the target class.
   local data = self:loadData(self._train_file, self._download_url)
   local start = 1
   local size = math.floor(data:size(1)*(1-self._valid_ratio))
   local train_data = data:narrow(1, start, size)
   self:setTrainSet(self:createDataSet(train_data, 'train'))
   return self:trainSet()
end

function Mnist:loadValid()
   local data = self:loadData(self._train_file, self._download_url)
   if self._valid_ratio == 0 then
      print"Warning : No Valid Set due to valid_ratio == 0"
      return
   end
   local start = math.ceil(data:size(1)*(1-self._valid_ratio))
   local size = data:size(1)-start
   local valid_data = data:narrow(1, start, size)
   self:setValidSet(self:createDataSet(valid_data, 'valid'))
   return self:validSet()
end

function Mnist:loadTest()
   local test_data = self:loadData(self._test_file, self._download_url)
   self:setTestSet(self:createDataSet(test_data, 'test'))
   return self:testSet()
end

--Creates an Mnist Dataset out of data and which_set
function Mnist:createDataSet(data, which_set)
   if self._shuffle then
      data = data:index(1, torch.randperm(data:size(1)):long())
   end
   local inputs = data:narrow(2, 1, self._feature_size):clone()
   inputs:resize(inputs:size(1), unpack(self._image_size))
   if self._binarize then
      DataSource.binarize(inputs, 128)
   end
   if self._scale and not self._binarize then
      DataSource.rescale(inputs, self._scale[1], self._scale[2])
   end
   local targets = data:select(2, self._feature_size+1):clone()
   -- class 0 will have index 1, class 1 index 2, and so on.
   targets:add(1)
   -- construct inputs and targets dp.Views 
   local input_v, target_v = dp.ImageView(), dp.ClassView()
   input_v:forward(self._image_axes, inputs)
   target_v:forward('b', targets)
   target_v:setClasses(self._classes)
   -- construct dataset
   return dp.DataSet{inputs=input_v,targets=target_v,which_set=which_set}
end


-- Get the raw, unprocessed data.
-- Returns a 60,000 x 785 tensor, where each image is 28*28 = 784 values in the
-- range [0-255], and the 785th element is the class ID.
function Mnist:loadData(file_name, download_url)
   local path = DataSource.getDataPath{
      name=self._name, url=download_url, decompress_file=file_name, 
      data_dir=self._data_path
   }
   local f = torch.DiskFile(path, 'r')
   f:binary()

   local n_examples   = f:readInt()
   local n_dimensions = f:readInt()

   local tensor = torch.Tensor(n_examples, n_dimensions)
   tensor:storage():copy(f:readFloat(n_examples * n_dimensions))
   return tensor
end


