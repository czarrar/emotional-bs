# # in script
# require 'mongoid'
# require SCRIPTDIR + 'etc/01_preprocessing/01_tables.rb'
# Mongoid.load!(SCRIPTDIR + "etc/mongoid.yml", :development)

require 'mongoid'

class Subject
  include Mongoid::Document
  
  field :name, type: String
  
  embeds_one :anatomical
end

class Anatomical
  include Mongoid::Document
  
  field :originals,   type: Array
  field :head,        type: String
  field :brain,       type: String
  field :brain_mask,  type: String
  field :pics_head,   type: Array
  field :pics_brain,  type: Array
  
  embedded_in :subject
end

#require 'mongo_mapper'
#
#class Subject
#  include MongoMapper::Document
#  
#  key :name, String
#  
#  has_one :anatomical
#end
#
#class Anatomical
#  include MongoMapper::EmbeddedDocument
#  
#  key :originals,   Array
#  key :head,        String
#  key :brain,       String
#  key :brain_mask,  String
#  key :pics_head,   Array
#  key :pics_brain,  Array
#  
#  # originals which can be an array
#  # head
#  # brain
#  # head_pic which is an array
#  # brain_pic which is an array
#  
#  embedded_in :subject
#end
