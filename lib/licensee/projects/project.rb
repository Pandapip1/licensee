# Licensee::Project represents an open source project on disk
# It is not used directly, but rather is extended by FSProject and GitProject
# depending on the type of file system access available
#
# Subclasses must implement the Files and LoadFile private methods
module Licensee
  module Projects
    class Project
      attr_reader :detect_readme, :detect_packages
      alias detect_readme? detect_readme
      alias detect_packages? detect_packages

      def initialize(detect_packages: false, detect_readme: false)
        @detect_packages = detect_packages
        @detect_readme = detect_readme
      end

      # Returns the matching License instance if a license can be detected
      def license
        return @license if defined? @license
        @license = if licenses.count == 1 || lgpl?
          licenses.first
        elsif licenses.count > 1
          Licensee::License.find('other')
        end
      end

      # Returns an array of detected Licenses
      def licenses
        @licenses ||= matched_files.map(&:license).uniq
      end

      # Returns the ProjectFile used to determine the License
      def matched_file
        matched_files.first if matched_files.count == 1 || lgpl?
      end

      # Returns an array of matches LicenseFiles
      def matched_files
        @matched_files ||= begin
          project_files.select(&:license)
        end
      end

      # Returns the LicenseFile used to determine the License
      def license_file
        license_files.first if license_files.count == 1 || lgpl?
      end

      def license_files
        @license_files ||= begin
          return [] if files.empty? || files.nil?
          files = find_files do |n|
            Licensee::ProjectFiles::LicenseFile.name_score(n)
          end
          files = files.map do |file|
            Licensee::ProjectFiles::LicenseFile.new(load_file(file), file)
          end

          prioritize_lgpl(files)
        end
      end

      def readme_file
        return unless detect_readme?
        return @readme if defined? @readme
        @readme = begin
          content, name = find_file do |n|
            Licensee::ProjectFiles::ReadmeFile.name_score(n)
          end
          content = Licensee::ProjectFiles::ReadmeFile.license_content(content)

          return unless content && name
          Licensee::ProjectFiles::ReadmeFile.new(content, name)
        end
      end
      alias readme readme_file

      def package_file
        return unless detect_packages?
        return @package_file if defined? @package_file
        @package_file = begin
          content, name = find_file do |n|
            Licensee::ProjectFiles::PackageManagerFile.name_score(n)
          end

          return unless content && name
          Licensee::ProjectFiles::PackageManagerFile.new(content, name)
        end
      end

      private

      def lgpl?
        return false unless licenses.count == 2 && license_files.count == 2
        license_files[0].lgpl? && license_files[1].gpl?
      end

      # Given a block, passes each filename to that block, and expects a numeric
      # score in response. Returns an array of all files with a score > 0,
      # sorted by file score descending
      def find_files
        return [] if files.empty? || files.nil?
        found = files.map { |file| file.merge(score: yield(file[:name])) }
        found.select! { |file| file[:score] > 0 }
        found.sort { |a, b| b[:score] <=> a[:score] }
      end

      # Given a block, passes each filename to that block, and expects a numeric
      # score in response. Returns a hash representing the top scoring file
      # or nil, if no file scored > 0
      def find_file(&block)
        return if files.empty? || files.nil?
        file = find_files(&block).first
        [load_file(file), file[:name]] if file
      end

      # Given an array of LicenseFiles, ensures LGPL is the first entry,
      # if the first entry is otherwise GPL, and a valid LGPL file exists
      #
      # This is becaues LGPL actually lives in COPYING.lesser, alongside an
      # otherwise GPL-licensed project, per the license instructions.
      # See https://git.io/viwyK.
      #
      # Returns an array of LicenseFiles with LPGL first
      def prioritize_lgpl(files)
        return files if files.empty?
        return files unless files.first.license && files.first.license.gpl?

        lesser = files.find_index(&:lgpl?)
        files.unshift(files.delete_at(lesser)) if lesser

        files
      end

      def project_files
        @project_files ||= [license_files, readme, package_file].flatten.compact
      end
    end

    def files
      raise 'Not implemented'
    end

    def load_file(_file)
      raise 'Not implemented'
    end
  end
end
