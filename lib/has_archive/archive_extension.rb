module HasArchive
  module ArchiveExtension
    def next
      owner = proxy_association.owner
      where('updated_at > ?', owner.updated_at)
        .order(updated_at: :asc)
        .first
    end

    def previous
      owner = proxy_association.owner
      where('updated_at < ?', owner.updated_at)
        .order(updated_at: :desc)
        .first
    end

    def latest
      owner = proxy_association.owner
      where("#{owner.has_archive_column}" => nil).first
    end
  end
end
